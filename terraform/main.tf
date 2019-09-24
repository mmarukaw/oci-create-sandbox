// Copyright (c) 2017, 2019, Oracle and/or its affiliates. All rights reserved.

variable base_compartment_name {
  default = "member"
}

variable users {
  type = list(object({
    name = string
    org  = map(string)
  }))
}

variable org_hierarchy {
  type = list(string)
}

locals {
  tagsbyusers = [
    for user in var.users : [
      for tagkey, tagvalue in user.org : [
        join("|", [lookup(user, "name"), tagkey])
      ]
    ]
  ]
}


resource "oci_identity_tag_namespace" "basic_tag_namespace" {
  name           = "basic"
  description    = "Tag namespace of basic tags"
  compartment_id = "${var.tenancy_ocid}"
}

resource "oci_identity_tag_namespace" "org_tag_namespace" {
  name           = "organization"
  description    = "Tag namespace of oraganization structure"
  compartment_id = "${var.tenancy_ocid}"
}

resource "oci_identity_tag" "created_by" {
  name             = "created_by"
  description      = "Tag key definition of resource creator's name"
  tag_namespace_id = "${oci_identity_tag_namespace.basic_tag_namespace.id}"
  is_cost_tracking = false
}

resource "oci_identity_tag" "owner" {
  name             = "owner"
  description      = "Tag key definition of owner in terms of cost"
  tag_namespace_id = "${oci_identity_tag_namespace.basic_tag_namespace.id}"
  is_cost_tracking = true
}

resource "oci_identity_tag" "org_hierarchy" {
  for_each         = toset(var.org_hierarchy)
  name             = "${each.value}"
  description      = "Tag key definition of ${each.value}"
  tag_namespace_id = "${oci_identity_tag_namespace.org_tag_namespace.id}"
  is_cost_tracking = true
}

resource "oci_identity_compartment" "base_compartment" {
  name           = "${var.base_compartment_name}"
  description    = "Base compartment for members"
  compartment_id = "${var.tenancy_ocid}"
  enable_delete  = false // true will cause this compartment to be deleted when running `terrafrom destroy`
}

resource "oci_identity_compartment" "member_compartments" {
  for_each       = toset([for user in var.users : lookup(user, "name")])
  name           = "${each.value}"
  description    = "Personal compartment for ${each.value}"
  compartment_id = "${oci_identity_compartment.base_compartment.id}"
  enable_delete  = false // true will cause this compartment to be deleted when running `terrafrom destroy`
}

resource "oci_identity_tag_default" "created_by_tag_defaults" {
  for_each          = toset([for user in var.users : lookup(user, "name")])
  tag_definition_id = "${oci_identity_tag.created_by.id}"
  value             = "$${iam.principal.name} ($${iam.principal.type})"
  compartment_id    = "${oci_identity_compartment.member_compartments[element(split("|", each.value), 0)].id}"
}

resource "oci_identity_tag_default" "owner_tag_defaults" {
  for_each          = toset([for user in var.users : lookup(user, "name")])
  tag_definition_id = "${oci_identity_tag.owner.id}"
  value             = "${each.value}"
  compartment_id    = "${oci_identity_compartment.member_compartments[element(split("|", each.value), 0)].id}"
}

resource "oci_identity_tag_default" "fy20_org_tag_defaults" {
  for_each          = toset(flatten(local.tagsbyusers))
  tag_definition_id = "${oci_identity_tag.org_hierarchy[element(split("|", each.value), 1)].id}"
  value             = "${lookup(element([for user in var.users : lookup(user, "org") if lookup(user, "name") == element(split("|", each.value), 0)], 0), element(split("|", each.value), 1))}"
  compartment_id    = "${oci_identity_compartment.member_compartments[element(split("|", each.value), 0)].id}"
}

resource "oci_identity_group" "admin_groups" {
  for_each       = toset([for user in var.users : lookup(user, "name")])
  name           = "${var.base_compartment_name}-${each.value}_admins"
  description    = "Administrator group for ${each.value}'s personal compartment"
  compartment_id = "${var.tenancy_ocid}"
}

data "oci_identity_identity_providers" "idcs_identity_provider" {
  compartment_id = "${var.tenancy_ocid}"
  protocol       = "SAML2"
}

resource "oci_identity_idp_group_mapping" "admin_idp_group_mappings" {
  for_each             = toset([for user in var.users : lookup(user, "name")])
  group_id             = "${oci_identity_group.admin_groups[each.key].id}"
  idp_group_name       = "oci_${oci_identity_group.admin_groups[each.key].name}"
  identity_provider_id = "${element([for provider in data.oci_identity_identity_providers.idcs_identity_provider.identity_providers[*] : provider.id if provider.name == "OracleIdentityCloudService"], 0)}"
}

resource "oci_identity_policy" "admin_policies" {
  count          = floor((length(var.users) - 1) / 50) + 1
  name           = "${var.base_compartment_name}_manage_policy_${count.index}"
  description    = "Management policy for members' personal compartments ${count.index}"
  compartment_id = "${oci_identity_compartment.base_compartment.id}"

  statements   = [for i in range(((count.index) * 50), min(((count.index + 1) * 50), length(var.users))) : "Allow group ${oci_identity_group.admin_groups[lookup(var.users[i], "name")].name} to manage all-resources in compartment ${oci_identity_compartment.member_compartments[lookup(var.users[i], "name")].name} where all{request.permission != 'COMPARTMENT_CREATE', request.permission != 'TAG_NAMESPACE_CREATE'}"]

}
/*
resource "oci_identity_policy" "admin_policies" {
  for_each       = toset([for user in var.users : lookup(user, "name")])
  name           = "${each.value}_manage_policy"
  description    = "Management policy for ${each.value}'s personal compartment"
  compartment_id = "${oci_identity_compartment.base_compartment.id}"
  statements     = [
    "Allow group ${oci_identity_group.admin_groups[each.key].name} to manage all-resources in compartment ${oci_identity_compartment.member_compartments[each.key].name} where all{request.permission != 'COMPARTMENT_CREATE', request.permission != 'TAG_NAMESPACE_CREATE'}"
  ]
}
*/
