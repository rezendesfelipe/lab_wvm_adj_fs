data "azurerm_resource_group" "vnet" {
  name = var.resource_group_name
}

resource "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  resource_group_name = data.azurerm_resource_group.vnet.name
  location            = var.location == null ? data.azurerm_resource_group.vnet.location : var.location
  address_space       = var.address_space
  dns_servers         = var.dns_servers
  tags                = var.tags
  depends_on          = [data.azurerm_resource_group.vnet]
}

resource "azurerm_subnet" "subnet" {
  for_each                                       = var.subnets
  name                                           = each.key
  resource_group_name                            = data.azurerm_resource_group.vnet.name
  virtual_network_name                           = azurerm_virtual_network.vnet.name
  address_prefixes                               = [each.value.address_prefix]
  service_endpoints                              = lookup(each.value, "service_endpoints", [])
  enforce_private_link_endpoint_network_policies = lookup(each.value, "enforce_private_link_endpoint_network_policies", null)
  enforce_private_link_service_network_policies  = lookup(each.value, "enforce_private_link_service_network_policies", null)
  dynamic "delegation" {
    for_each = lookup(each.value, "delegation", {}) != {} ? [1] : []
    content {
      name = lookup(each.value.delegation, "name", null)
      service_delegation {
        name    = lookup(each.value.delegation.service_delegation, "name", null)
        actions = lookup(each.value.delegation.service_delegation, "actions", null)
      }
    }
  }
}

locals {
  azurerm_subnets = {
    for index, subnet in azurerm_subnet.subnet :
    subnet.name => subnet.id
  }
  nsgs = {
    for index, nsg in module.nsg_subnet :
    nsg.nsg_name => nsg.nsg_id
  }
  rts = {
    for index, rt in azurerm_route_table.rt :
    rt.name => rt.id
  }
}

# This configuration block prepares NSGs for each declared subnet inside the variable "nsg_subnet"
module "nsg_subnet" {
  for_each = { for k, v in var.subnets : k => v if k != "GatewaySubnet" && k != "AzureFirewallSubnet" && k != "AzureBastionSubnet" } # For each subnet, an NSG is mandatory to be created

  source = "git::git@ssh.dev.azure.com:v3/swonelab/Modulos_Terraform/terraform-azurerm-network-security-group?ref=v1.0.0"

  resource_group_name = data.azurerm_resource_group.vnet.name
  location            = var.location == null ? data.azurerm_resource_group.vnet.location : var.location
  tags                = var.tags

  nsg_name = each.value.nsg_name
  rules    = lookup(each.value, "nsg_rules", {})

  depends_on = [
    data.azurerm_resource_group.vnet
  ]
}

resource "azurerm_route_table" "rt" {

  for_each = {
    for k, v in var.subnets : k => v if v.routes != {}
  }
  resource_group_name = data.azurerm_resource_group.vnet.name
  location            = var.location == null ? data.azurerm_resource_group.vnet.location : var.location
  tags                = var.tags

  depends_on = [
    data.azurerm_resource_group.vnet
  ]

  name                          = join("-", ["rt", each.key])
  disable_bgp_route_propagation = lookup(each.value, "disable_bgp_route_propagation", false)

  dynamic "route" {
    for_each = lookup(each.value, "routes", {}) == {} ? {} : lookup(each.value, "routes", {})
    content {
      name                   = route.key
      address_prefix         = route.value.address_prefix
      next_hop_type          = lookup(route.value, "next_hop_type", "None")
      next_hop_in_ip_address = lookup(route.value, "next_hop_in_ip_address", null)
    }
  }

}

resource "azurerm_subnet_network_security_group_association" "vnet" {
  for_each                  = module.nsg_subnet
  subnet_id                 = local.azurerm_subnets[each.key]
  network_security_group_id = each.value.nsg_id # This will collect each NSG id from the output from above
}

resource "azurerm_subnet_route_table_association" "vnet" {
  for_each       = azurerm_route_table.rt
  subnet_id      = local.azurerm_subnets[each.key]
  route_table_id = each.value.id
}

resource "azurerm_virtual_network_peering" "vnet" {
  for_each = var.vnet_peering_settings == null ? {} : var.vnet_peering_settings

  resource_group_name          = var.resource_group_name
  remote_virtual_network_id    = each.value.remote_vnet_id
  virtual_network_name         = azurerm_virtual_network.vnet.name
  name                         = each.key
  allow_forwarded_traffic      = lookup(each.value, "allow_forwarded_traffic", true)
  allow_virtual_network_access = lookup(each.value, "allow_virtual_network_access", true)
  allow_gateway_transit        = lookup(each.value, "allow_gateway_transit", false)
  use_remote_gateways          = lookup(each.value, "use_remote_gateways", false)

  depends_on = [
    azurerm_virtual_network.vnet,
    data.azurerm_resource_group.vnet
  ]
}