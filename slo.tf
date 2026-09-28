# User story: "As a service owner, when I deploy or scale a workload, my pods are
# placed on a node within 5 minutes, even when new capacity has to be launched."
#
# SLI = pods bound within var.sli_threshold_seconds / all pods bound
# (karpenter_pods_bound_duration_seconds, a histogram from pod creation to binding).

resource "signalfx_slo" "pod_scheduling" {
  for_each    = toset(var.clusters)
  name        = "Karpenter pod scheduling latency - ${each.key}"
  description = "${var.slo_target}% of pods are bound to a node within ${var.sli_threshold_seconds}s over 30 days."
  type        = "RequestBased"

  input {
    program_text       = <<-EOF
      G = data('karpenter_pods_bound_duration_seconds_bucket', filter=${local.le_filter} and filter('${local.cluster}', '${each.key}'), rollup='delta').sum()
      T = data('karpenter_pods_bound_duration_seconds_count', filter=filter('${local.cluster}', '${each.key}'), rollup='delta').sum()
    EOF
    good_events_label  = "G"
    total_events_label = "T"
  }

  target {
    type              = "RollingWindow"
    slo               = var.slo_target
    compliance_period = "30d"

    alert_rule {
      type = "BREACH"
      rule {
        severity      = "Critical"
        notifications = var.notifications
      }
    }
  }
}

# Multi-window burn-rate alerts (Google SRE workbook: 14.4x over 1h/5m, 6x over 6h/30m).
# Kept as a plain detector so it covers every cluster in one place.
resource "signalfx_detector" "slo_burn_rate" {
  name         = "Karpenter - pod scheduling SLO burn rate"
  description  = "Error budget for '${var.slo_target}% of pods bound within ${var.sli_threshold_seconds}s' is burning too fast."
  program_text = <<-EOF
    G = data('karpenter_pods_bound_duration_seconds_bucket', filter=${local.le_filter}, rollup='delta').sum(${local.by})
    T = data('karpenter_pods_bound_duration_seconds_count', rollup='delta').sum(${local.by})
    budget = 1 - ${var.slo_target} / 100
    B5m  = (1 - G.sum(over='5m')  / T.sum(over='5m'))  / budget
    B30m = (1 - G.sum(over='30m') / T.sum(over='30m')) / budget
    B1h  = (1 - G.sum(over='1h')  / T.sum(over='1h'))  / budget
    B6h  = (1 - G.sum(over='6h')  / T.sum(over='6h'))  / budget
    detect(when(B1h > 14.4) and when(B5m > 14.4)).publish('Fast burn')
    detect(when(B6h > 6) and when(B30m > 6)).publish('Slow burn')
  EOF

  rule {
    detect_label  = "Fast burn"
    severity      = "Critical"
    notifications = var.notifications
    runbook_url   = var.runbook_url
  }
  rule {
    detect_label  = "Slow burn"
    severity      = "Major"
    notifications = var.notifications
    runbook_url   = var.runbook_url
  }
}
