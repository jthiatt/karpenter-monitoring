resource "signalfx_detector" "karpenter_down" {
  name         = "Karpenter - controller down / not synced"
  description  = "Karpenter stopped reporting metrics, or its view of cluster state is out of sync. No new nodes will be provisioned."
  program_text = <<-EOF
    from signalfx.detectors.not_reported import not_reported
    H = data('karpenter_cluster_state_node_count').sum(${local.by})
    S = data('karpenter_cluster_state_synced').max(${local.by})
    not_reported.detector(stream=H, resource_identifier=['${local.cluster}'], duration='10m').publish('Karpenter not reporting')
    detect(when(S < 1, lasting='15m')).publish('Karpenter cluster state not synced')
  EOF

  rule {
    detect_label  = "Karpenter not reporting"
    severity      = "Critical"
    notifications = var.notifications
    runbook_url   = var.runbook_url
  }
  rule {
    detect_label  = "Karpenter cluster state not synced"
    severity      = "Major"
    notifications = var.notifications
    runbook_url   = var.runbook_url
  }
}

resource "signalfx_detector" "pending_pods" {
  name         = "Karpenter - pods stuck pending"
  description  = "More than ${var.pending_pods_threshold} pods Pending for 15m: Karpenter is not providing capacity fast enough (or at all)."
  program_text = <<-EOF
    P = data('k8s.pod.phase', rollup='latest').below(1, inclusive=True).count(${local.by})
    detect(when(P > ${var.pending_pods_threshold}, lasting='15m')).publish('Pods stuck pending')
  EOF

  rule {
    detect_label  = "Pods stuck pending"
    severity      = "Major"
    notifications = var.notifications
    runbook_url   = var.runbook_url
  }
}

resource "signalfx_detector" "cloudprovider_errors" {
  name         = "Karpenter - cloud provider (EC2) API errors"
  description  = "Sustained EC2 API errors: throttling, IAM, insufficient capacity, or launch template problems."
  program_text = <<-EOF
    E = data('karpenter_cloudprovider_errors_total', rollup='delta').sum(${local.by}).sum(over='10m')
    detect(when(E > ${var.cloudprovider_errors_threshold}, lasting='10m')).publish('Cloud provider errors')
  EOF

  rule {
    detect_label  = "Cloud provider errors"
    severity      = "Major"
    notifications = var.notifications
    runbook_url   = var.runbook_url
  }
}

resource "signalfx_detector" "reconcile_errors" {
  name         = "Karpenter - controller reconcile errors"
  description  = "Karpenter controllers are failing reconciles continuously."
  program_text = <<-EOF
    E = data('controller_runtime_reconcile_errors_total', filter=filter('k8s.namespace.name', '${var.karpenter_namespace}'), rollup='delta').sum(by=['${local.cluster}', 'controller']).sum(over='10m')
    detect(when(E > 5, lasting='20m')).publish('Reconcile errors')
  EOF

  rule {
    detect_label  = "Reconcile errors"
    severity      = "Warning"
    notifications = var.notifications
    runbook_url   = var.runbook_url
  }
}

resource "signalfx_detector" "nodepool_limits" {
  name         = "Karpenter - NodePool approaching limit"
  description  = "A NodePool is near/at its resource limit; Karpenter will stop provisioning nodes for it."
  program_text = <<-EOF
    U = data('karpenter_nodepools_usage').sum(by=['${local.cluster}', 'nodepool', 'resource_type'])
    L = data('karpenter_nodepools_limit').sum(by=['${local.cluster}', 'nodepool', 'resource_type'])
    R = U / L
    detect(when(R >= 0.9, lasting='15m'), off=when(R < 0.85, lasting='15m')).publish('NodePool > 90% of limit')
    detect(when(R >= 1, lasting='5m')).publish('NodePool at limit')
  EOF

  rule {
    detect_label  = "NodePool > 90% of limit"
    severity      = "Warning"
    notifications = var.notifications
    runbook_url   = var.runbook_url
  }
  rule {
    detect_label  = "NodePool at limit"
    severity      = "Major"
    notifications = var.notifications
    runbook_url   = var.runbook_url
  }
}

resource "signalfx_detector" "disruption_thrash" {
  name         = "Karpenter - node disruption thrash"
  description  = "Unusually high node churn from consolidation/drift. Check PDBs, consolidation settings and disruption budgets."
  program_text = <<-EOF
    D = data('karpenter_nodeclaims_disrupted_total', rollup='delta').sum(${local.by}).sum(over='1h')
    detect(when(D > ${var.disruptions_per_hour_threshold}, lasting='15m')).publish('Disruption thrash')
  EOF

  rule {
    detect_label  = "Disruption thrash"
    severity      = "Warning"
    notifications = var.notifications
    runbook_url   = var.runbook_url
  }
}

resource "signalfx_detector" "slow_scheduling" {
  name         = "Karpenter - slow scheduling simulations"
  description  = "Karpenter's scheduling loop is slow; provisioning latency will grow. Often CPU throttling of the controller or huge pending batches."
  program_text = <<-EOF
    S = data('karpenter_scheduler_scheduling_duration_seconds_sum', rollup='delta').sum(${local.by}).sum(over='10m')
    C = data('karpenter_scheduler_scheduling_duration_seconds_count', rollup='delta').sum(${local.by}).sum(over='10m')
    detect(when(S / C > 30, lasting='15m')).publish('Slow scheduling')
  EOF

  rule {
    detect_label  = "Slow scheduling"
    severity      = "Warning"
    notifications = var.notifications
    runbook_url   = var.runbook_url
  }
}
