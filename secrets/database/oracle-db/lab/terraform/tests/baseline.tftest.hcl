# Offline infrastructure/input checks. Mock providers never contact AWS.
mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a"] }
  }
  mock_data "aws_ami" {
    defaults = { id = "ami-00000000000000001" }
  }
  mock_data "aws_ec2_instance_type" {
    defaults = { supported_architectures = ["x86_64"], memory_size = 8192 }
  }
}

variables {
  key_name       = "offline-test-key"
  admin_ssh_cidr = "127.0.0.1/32"
  vault_license  = "offline-test-placeholder"
}

run "default_baseline" {
  command = plan
  assert {
    condition     = output.baseline.static_roles == 100 && output.baseline.dynamic_roles == 100 && length(aws_instance.lab) == 1
    error_message = "The standard baseline must request 100 roles of each kind on one Vault node."
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.ssh.from_port == 22 && aws_vpc_security_group_ingress_rule.ssh.to_port == 22
    error_message = "The baseline should expose SSH, with Oracle and Vault accessed from the guest."
  }
  assert {
    condition     = aws_instance.lab[0].root_block_device[0].encrypted && aws_instance.lab[0].user_data_replace_on_change
    error_message = "Lab data must be encrypted and bootstrap changes must produce a fresh baseline."
  }
}

run "small_versioned_baseline" {
  command = plan
  variables {
    vault_version         = "1.21.9+ent"
    oracle_plugin_version = "0.11.0+ent"
    static_role_count     = 2
    dynamic_role_count    = 3
    ami_id                = "ami-00000000000000002"
  }
  assert {
    condition     = output.baseline.static_roles == 2 && output.baseline.dynamic_roles == 3 && output.baseline.vault_version == "1.21.9+ent" && aws_instance.lab[0].ami == "ami-00000000000000002"
    error_message = "Scenario version, independent counts and pinned AMI must reach the baseline."
  }
}

run "render_complete_bootstrap" {
  # Mock apply resolves the KMS ID and exercises the full compressed user-data
  # precondition. Plan alone defers it because the KMS ID is not yet known.
  command = apply
  assert {
    condition     = length(aws_instance.lab[0].user_data_base64) <= 21844
    error_message = "Rendered and compressed bootstrap must fit the EC2 user-data limit."
  }
}

run "three_voter_baseline" {
  command = apply
  variables { vault_node_count = 3 }
  assert {
    condition     = length(aws_instance.lab) == 3 && length(distinct(aws_instance.lab[*].private_ip)) == 3
    error_message = "Three-node mode must create three distinct Raft hosts."
  }
  assert {
    condition     = length([for node in output.vault_nodes : node if node.hosts_oracle]) == 1 && alltrue([for config in local.node_configs : config.oracle_host == local.nodes[0].private_ip])
    error_message = "All Vault nodes must share the one Oracle instance hosted on node 1."
  }
  assert {
    condition     = [for config in local.node_configs : config.node_index] == [0, 1, 2] && alltrue([for config in local.node_configs : length(config.nodes) == 3])
    error_message = "Only index 0 initializes/populates; followers need the complete peer topology."
  }
  assert {
    condition     = alltrue([for node in aws_instance.lab : length(node.user_data_base64) <= 21844]) && length(distinct(aws_instance.lab[*].user_data_base64)) == 3
    error_message = "Every node needs a distinct, size-bounded bootstrap payload."
  }
  assert {
    condition     = alltrue([for rule in aws_vpc_security_group_ingress_rule.members : rule.referenced_security_group_id == aws_security_group.lab.id && rule.cidr_ipv4 == null])
    error_message = "Application ports must be restricted to lab members, not public CIDRs."
  }
}

run "reject_two_voters" {
  command = plan
  variables { vault_node_count = 2 }
  expect_failures = [var.vault_node_count]
}

run "reject_fractional_voters" {
  command = plan
  variables { vault_node_count = 1.5 }
  expect_failures = [var.vault_node_count]
}

run "reject_fractional_roles" {
  command = plan
  variables { static_role_count = 1.5 }
  expect_failures = [var.static_role_count]
}

run "reject_empty_dynamic_population" {
  command = plan
  variables { dynamic_role_count = 0 }
  expect_failures = [var.dynamic_role_count]
}

run "reject_unsupported_vault_version" {
  command = plan
  variables { vault_version = "1.19.9+ent" }
  expect_failures = [var.vault_version]
}

run "reject_unrestricted_ssh" {
  command = plan
  variables { admin_ssh_cidr = "0.0.0.0/0" }
  expect_failures = [var.admin_ssh_cidr]
}

run "reject_arm_guest" {
  command = plan
  override_data {
    target = data.aws_ec2_instance_type.selected
    values = { supported_architectures = ["arm64"], memory_size = 8192 }
  }
  expect_failures = [aws_instance.lab]
}

run "reject_undersized_guest" {
  command = plan
  override_data {
    target = data.aws_ec2_instance_type.selected
    values = { supported_architectures = ["x86_64"], memory_size = 4096 }
  }
  expect_failures = [aws_instance.lab]
}
