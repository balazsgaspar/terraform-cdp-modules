# Copyright 2023 Cloudera, Inc. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# ------- Azure Resource Group -------
resource "azurerm_resource_group" "cdp_rmgp" {
  name     = local.resourcegroup_name
  location = var.azure_region

  tags = merge(local.env_tags, { Name = local.resourcegroup_name })
}

# ------- VNet -------
# TODO: Move this to a sub-module & find existing TF modules
# https://github.com/Azure/terraform-azurerm-network
resource "azurerm_virtual_network" "cdp_vnet" {
  name                = local.vnet_name
  location            = azurerm_resource_group.cdp_rmgp.location
  resource_group_name = azurerm_resource_group.cdp_rmgp.name
  address_space       = [var.vnet_cidr]
  dns_servers         = []

  tags = merge(local.env_tags, { Name = local.vnet_name })
}

# ------- Subnets -------
# TODO: Revisit need for pub vs. priv subnet
# TODO: Better planning of VNet & subnets as per: https://docs.cloudera.com/cdp-public-cloud/cloud/requirements-azure/topics/mc-azure-vnet-and-subnets.html

# Azure VNet Public Subnets
resource "azurerm_subnet" "cdp_public_subnets" {

  for_each = { for idx, subnet in local.public_subnets : idx => subnet }

  virtual_network_name = azurerm_virtual_network.cdp_vnet.name
  resource_group_name  = azurerm_resource_group.cdp_rmgp.name
  name                 = each.value.name
  address_prefixes     = [each.value.cidr]

  service_endpoints                         = ["Microsoft.Sql", "Microsoft.Storage"]
  private_endpoint_network_policies_enabled = true

}

# Azure VNet Pricate Subnets
resource "azurerm_subnet" "cdp_private_subnets" {

  for_each = { for idx, subnet in local.private_subnets : idx => subnet }

  virtual_network_name = azurerm_virtual_network.cdp_vnet.name
  resource_group_name  = azurerm_resource_group.cdp_rmgp.name
  name                 = each.value.name
  address_prefixes     = [each.value.cidr]

  service_endpoints                         = ["Microsoft.Sql", "Microsoft.Storage"]
  private_endpoint_network_policies_enabled = true

}

# ------- Security Groups -------
# Default SG
resource "azurerm_network_security_group" "cdp_default_sg" {
  name                = local.security_group_default_name
  location            = azurerm_resource_group.cdp_rmgp.location
  resource_group_name = azurerm_resource_group.cdp_rmgp.name

  tags = merge(local.env_tags, { Name = local.security_group_default_name })

}

# Create security group rules for CDP control plane ingress
# TODO: This may not be needed with CCMv2
resource "azurerm_network_security_rule" "cdp_default_sg_ingress_cdp_control_plane" {
  name                        = "AllowAccessForCDPControlPlane"
  priority                    = 901
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_address_prefixes     = var.cdp_control_plane_cidrs
  destination_address_prefix  = "*"
  source_port_range           = "*"
  destination_port_ranges     = [443, 9443]
  resource_group_name         = azurerm_resource_group.cdp_rmgp.name
  network_security_group_name = azurerm_network_security_group.cdp_default_sg.name
}

# Create security group rules for extra list of ingress rules
# TODO: How to handle the case where ingress_extra_cidrs_and_ports is []
resource "azurerm_network_security_rule" "cdp_default_sg_ingress_extra_access" {
  name                        = "AllowAccessForExtraCidrsAndPorts"
  priority                    = 201
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_address_prefixes     = var.ingress_extra_cidrs_and_ports.cidrs
  destination_address_prefix  = "*"
  source_port_range           = "*"
  destination_port_ranges     = var.ingress_extra_cidrs_and_ports.ports
  resource_group_name         = azurerm_resource_group.cdp_rmgp.name
  network_security_group_name = azurerm_network_security_group.cdp_default_sg.name
}

# Knox SG
resource "azurerm_network_security_group" "cdp_knox_sg" {
  name                = local.security_group_knox_name
  location            = azurerm_resource_group.cdp_rmgp.location
  resource_group_name = azurerm_resource_group.cdp_rmgp.name

  tags = merge(local.env_tags, { Name = local.security_group_knox_name })

}

# Create security group rules for CDP control plane ingress
# TODO: This may not be needed with CCMv2
resource "azurerm_network_security_rule" "cdp_knox_sg_ingress_cdp_control_plane" {
  name                        = "AllowAccessForCDPControlPlane"
  priority                    = 901
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_address_prefixes     = var.cdp_control_plane_cidrs
  destination_address_prefix  = "*"
  source_port_range           = "*"
  destination_port_ranges     = [443, 9443]
  resource_group_name         = azurerm_resource_group.cdp_rmgp.name
  network_security_group_name = azurerm_network_security_group.cdp_knox_sg.name
}

# Create security group rules for extra list of ingress rules
# TODO: How to handle the case where ingress_extra_cidrs_and_ports is []
resource "azurerm_network_security_rule" "cdp_knox_sg_ingress_extra_access" {
  name                        = "AllowAccessForExtraCidrsAndPorts"
  priority                    = 201
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_address_prefixes     = var.ingress_extra_cidrs_and_ports.cidrs
  destination_address_prefix  = "*"
  source_port_range           = "*"
  destination_port_ranges     = var.ingress_extra_cidrs_and_ports.ports
  resource_group_name         = azurerm_resource_group.cdp_rmgp.name
  network_security_group_name = azurerm_network_security_group.cdp_knox_sg.name
}


# ------- Azure Storage Account -------
resource "random_id" "bucket_suffix" {
  count = var.random_id_for_bucket ? 1 : 0

  byte_length = 4
}

resource "azurerm_storage_account" "cdp_storage_locations" {
  # Create buckets for the unique list of buckets in data and log storage
  for_each = toset(concat([local.data_storage.data_storage_bucket], [local.log_storage.log_storage_bucket], [local.backup_storage.backup_storage_bucket]))

  name                = "${each.value}${local.storage_suffix}"
  resource_group_name = azurerm_resource_group.cdp_rmgp.name
  location            = azurerm_resource_group.cdp_rmgp.location

  # TODO: Review and parameterize these options
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"
  is_hns_enabled           = true

  tags = merge(local.env_tags, { Name = "${each.value}${local.storage_suffix}" })
}

# ------- Azure Storage Containers -------
# Data Storage Objects
resource "azurerm_storage_container" "cdp_data_storage" {

  name                  = local.data_storage.data_storage_object
  storage_account_name  = "${local.data_storage.data_storage_bucket}${local.storage_suffix}"
  container_access_type = "private"

  depends_on = [
    azurerm_storage_account.cdp_storage_locations
  ]
}

# Log Storage Objects
resource "azurerm_storage_container" "cdp_log_storage" {

  name                  = local.log_storage.log_storage_object
  storage_account_name  = "${local.log_storage.log_storage_bucket}${local.storage_suffix}"
  container_access_type = "private"

  depends_on = [
    azurerm_storage_account.cdp_storage_locations
  ]
}

# Backup Storage Object
resource "azurerm_storage_container" "cdp_backup_storage" {

  name                  = local.backup_storage.backup_storage_object
  storage_account_name  = "${local.backup_storage.backup_storage_bucket}${local.storage_suffix}"
  container_access_type = "private"

  depends_on = [
    azurerm_storage_account.cdp_storage_locations
  ]
}
