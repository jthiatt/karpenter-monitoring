variable "sfx_auth_token" {
  type      = string
  sensitive = true
}

variable "sfx_api_url" {
  description = "Splunk Observability API URL for your realm, e.g. https://api.us1.signalfx.com"
  type        = string
}

variable "splunk_url" {
  description = "Splunk Core management endpoint host:port, e.g. splunk.example.com:8089"
  type        = string
}

variable "splunk_auth_token" {
  type      = string
  sensitive = true
}

variable "clusters" {
  description = "EKS cluster names (values of var.cluster_dimension). One SLO is created per cluster."
  type        = list(string)
}

variable "cluster_dimension" {
  description = "Metric dimension holding the cluster name (Splunk OTel Collector default)."
  type        = string
  default     = "k8s.cluster.name"
}

variable "karpenter_namespace" {
  type    = string
  default = "karpenter"
}

variable "notifications" {
  description = "Splunk o11y notification targets, e.g. [\"Email,oncall@example.com\", \"PagerDuty,<credentialId>\"]"
  type        = list(string)
}

variable "runbook_url" {
  type    = string
  default = ""
}

# ---- SLO ----
variable "sli_threshold_seconds" {
  description = "A pod counts as 'good' if bound to a node within this many seconds. Must be a Karpenter histogram bucket boundary."
  type        = number
  default     = 300
  validation {
    condition     = contains([60, 90, 120, 150, 180, 210, 240, 270, 300, 360, 420, 480, 540, 600, 900], var.sli_threshold_seconds)
    error_message = "Must be a karpenter_pods_bound_duration_seconds bucket boundary."
  }
}

variable "slo_target" {
  description = "SLO target percent."
  type        = number
  default     = 99.5
}

# ---- Detector thresholds ----
variable "pending_pods_threshold" {
  type    = number
  default = 5
}

variable "cloudprovider_errors_threshold" {
  description = "Cloud provider API errors per 10m before alerting."
  type        = number
  default     = 10
}

variable "disruptions_per_hour_threshold" {
  description = "Node disruptions per hour that indicate consolidation thrash."
  type        = number
  default     = 50
}

# ---- Splunk Core ----
variable "log_index" {
  type    = string
  default = "k8s"
}

variable "log_base_search" {
  description = "Base SPL that returns Karpenter controller logs. Default matches the Splunk OTel Collector's HEC fields."
  type        = string
  default     = ""
}

variable "alert_email" {
  description = "Email for Splunk Core log alerts."
  type        = string
}
