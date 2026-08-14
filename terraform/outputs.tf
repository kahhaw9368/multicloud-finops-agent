# -----------------------------------------------------------------------------
# AIOps MCP Gateway Proxy - Outputs
# -----------------------------------------------------------------------------

# AgentCore Gateway Outputs
output "gateway_id" {
  description = "AgentCore Gateway ID"
  value       = module.agentcore_gateway.gateway_id
}

output "gateway_endpoint" {
  description = "MCP Gateway URL for client configuration (use this in .mcp.json)"
  value       = module.agentcore_gateway.gateway_url
}

# -----------------------------------------------------------------------------
# MCP Lambda Server Outputs
# -----------------------------------------------------------------------------

output "mcp_cost_explorer_lambda_arn" {
  description = "Cost Explorer MCP Lambda function ARN"
  value       = module.mcp_cost_explorer.function_arn
}

output "mcp_athena_lambda_arn" {
  description = "Athena MCP Lambda function ARN"
  value       = module.mcp_athena.function_arn
}

output "mcp_cloudwatch_lambda_arn" {
  description = "CloudWatch metrics MCP Lambda function ARN"
  value       = module.mcp_cloudwatch.function_arn
}

output "mcp_target_ids" {
  description = "Map of MCP Lambda target names to their target IDs"
  value       = module.agentcore_gateway.mcp_target_ids
}

# Everything scripts/update_tool_schemas.py needs to re-register full tool
# schemas against each Gateway target: schema filename, description, and
# Lambda ARN. Derived from `local.mcp_lambda_targets`, so renaming a target or
# swapping a schema file can't drift from the post-apply registration.
output "gateway_target_schemas" {
  description = "Map of Gateway target name to {schema_file, description, lambda_arn}"
  value = {
    for t in local.mcp_lambda_targets : t.name => {
      schema_file = local.tool_schema_files[t.name]
      description = t.description
      lambda_arn  = t.lambda_arn
    }
  }
}

# Summary for MCP Client Configuration
output "mcp_client_config" {
  description = "Example MCP client configuration for .mcp.json"
  value = {
    gateway_endpoint = module.agentcore_gateway.gateway_url
    auth_type        = var.gateway_auth_type
    targets = {
      cost_explorer = "cost-explorer-mcp"
      athena        = "athena-mcp"
      cloudwatch    = "cloudwatch-mcp"
    }
  }
}

# -----------------------------------------------------------------------------
# Cross-Account Configuration Outputs
# -----------------------------------------------------------------------------

output "management_role_arn" {
  description = "IAM role ARN in management account (for cross-account access)"
  value       = local.management_role_arn
}

output "cross_account_external_id" {
  description = "External ID for cross-account role assumption (save this securely!)"
  value       = local.cross_account_external_id
  sensitive   = true
}

output "cross_account_enabled" {
  description = "Whether cross-account deployment is enabled"
  value       = var.management_account_profile != ""
}

# -----------------------------------------------------------------------------
# Cognito Gateway Auth Outputs (populated when gateway_auth_type = COGNITO)
# -----------------------------------------------------------------------------

output "gateway_cognito_client_id" {
  description = "OAuth client_id — paste into QuickSuite / M2M caller config"
  value       = length(module.cognito_gateway_auth) > 0 ? module.cognito_gateway_auth[0].client_id : null
}

output "gateway_cognito_client_secret" {
  description = "OAuth client_secret — paste into QuickSuite / M2M caller config"
  value       = length(module.cognito_gateway_auth) > 0 ? module.cognito_gateway_auth[0].client_secret : null
  sensitive   = true
}

output "gateway_cognito_token_url" {
  description = "OAuth token endpoint"
  value       = length(module.cognito_gateway_auth) > 0 ? module.cognito_gateway_auth[0].token_url : null
}

output "gateway_cognito_scope" {
  description = "OAuth scope (<resource_server>/<scope_name>)"
  value       = length(module.cognito_gateway_auth) > 0 ? module.cognito_gateway_auth[0].scope : null
}

output "gateway_cognito_discovery_url" {
  description = "OIDC discovery URL (informational)"
  value       = length(module.cognito_gateway_auth) > 0 ? module.cognito_gateway_auth[0].discovery_url : null
}
