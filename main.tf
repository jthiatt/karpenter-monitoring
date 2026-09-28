terraform {
  required_version = ">= 1.5"
  required_providers {
    signalfx = {
      source  = "splunk-terraform/signalfx"
      version = "~> 9.0"
    }
    splunk = {
      source  = "splunk/splunk"
      version = "~> 1.4"
    }
  }
}

provider "signalfx" {
  auth_token = var.sfx_auth_token
  api_url    = var.sfx_api_url
}

provider "splunk" {
  url                  = var.splunk_url
  auth_token           = var.splunk_auth_token
  insecure_skip_verify = false
}

locals {
  cluster = var.cluster_dimension
  by      = "by=['${var.cluster_dimension}']"

  # SLI: pods bound (scheduled) within var.sli_threshold_seconds.
  # `le` is emitted as "300" or "300.0" depending on collector version, so match both.
  le_filter = "filter('le', '${var.sli_threshold_seconds}', '${var.sli_threshold_seconds}.0')"

  log_search = coalesce(var.log_base_search,
  "index=${var.log_index} k8s.namespace.name=\"${var.karpenter_namespace}\" k8s.container.name=\"controller\" | spath")
}
