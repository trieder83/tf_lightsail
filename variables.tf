variable "aws_availability_zone_a"  {
  description = "first availability_zone"
  type = string
  default = "eu-central-1a"
}

variable "ssh_wg_key_private" {
  description = "ssh private key name"
  type = string
  default = "wg_vpn.key"
}
