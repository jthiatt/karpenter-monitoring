resource "signalfx_dashboard_group" "karpenter" {
  name        = "Karpenter"
  description = "Karpenter node autoscaling health, capacity and SLO (managed by Terraform)"
}

# ---------------- Overview ----------------

resource "signalfx_single_value_chart" "nodes" {
  name         = "Karpenter-managed nodes"
  program_text = "data('karpenter_cluster_state_node_count').sum().publish('Nodes')"
}

resource "signalfx_single_value_chart" "synced" {
  name         = "Cluster state synced (1 = healthy)"
  program_text = "data('karpenter_cluster_state_synced').min().publish('Synced')"
  color_by     = "Scale"
  color_scale {
    lte   = 0
    color = "red"
  }
  color_scale {
    gt    = 0
    color = "green"
  }
}

resource "signalfx_single_value_chart" "sli" {
  name          = "SLI: pods bound < ${var.sli_threshold_seconds}s (1h)"
  unit_prefix   = "Metric"
  max_precision = 4
  program_text  = <<-EOF
    G = data('karpenter_pods_bound_duration_seconds_bucket', filter=${local.le_filter}, rollup='delta').sum().sum(over='1h')
    T = data('karpenter_pods_bound_duration_seconds_count', rollup='delta').sum().sum(over='1h')
    (G / T * 100).publish('SLI %')
  EOF
}

locals {
  overview_charts = {
    sli = {
      name    = "SLI: % pods bound < ${var.sli_threshold_seconds}s (1h rolling) vs target"
      program = <<-EOF
        G = data('karpenter_pods_bound_duration_seconds_bucket', filter=${local.le_filter}, rollup='delta').sum(${local.by}).sum(over='1h')
        T = data('karpenter_pods_bound_duration_seconds_count', rollup='delta').sum(${local.by}).sum(over='1h')
        (G / T * 100).publish('SLI %')
        const(${var.slo_target}).publish('Target')
      EOF
    }
    pending = {
      name    = "Pending pods"
      program = "data('k8s.pod.phase', rollup='latest').below(1, inclusive=True).count(${local.by}).publish('Pending')"
    }
    queue = {
      name    = "Scheduler queue depth"
      program = "data('karpenter_scheduler_queue_depth').sum(${local.by}).publish('Queue')"
    }
    sched_duration = {
      name    = "Avg scheduling simulation duration (s)"
      program = <<-EOF
        S = data('karpenter_scheduler_scheduling_duration_seconds_sum', rollup='delta').sum(${local.by})
        C = data('karpenter_scheduler_scheduling_duration_seconds_count', rollup='delta').sum(${local.by})
        (S / C).publish('Avg seconds')
      EOF
    }
    cloud_errors = {
      name    = "Cloud provider errors by method/error"
      program = "data('karpenter_cloudprovider_errors_total', rollup='delta').sum(by=['${local.cluster}', 'method', 'error']).publish('Errors')"
    }
    reconcile_errors = {
      name    = "Controller reconcile errors by controller"
      program = "data('controller_runtime_reconcile_errors_total', filter=filter('k8s.namespace.name', '${var.karpenter_namespace}'), rollup='delta').sum(by=['${local.cluster}', 'controller']).publish('Errors')"
    }
  }

  capacity_charts = {
    nodes_capacity_type = {
      name    = "Nodes by capacity type (spot / on-demand)"
      program = "data('karpenter_nodes_allocatable', filter=filter('resource_type', 'cpu')).count(by=['${local.cluster}', 'capacity_type']).publish('Nodes')"
    }
    nodes_nodepool = {
      name    = "Nodes by NodePool"
      program = "data('karpenter_nodes_allocatable', filter=filter('resource_type', 'cpu')).count(by=['${local.cluster}', 'nodepool']).publish('Nodes')"
    }
    created = {
      name    = "NodeClaims created"
      program = "data('karpenter_nodeclaims_created_total', rollup='delta').sum(by=['${local.cluster}', 'nodepool']).publish('Created')"
    }
    terminated = {
      name    = "NodeClaims terminated"
      program = "data('karpenter_nodeclaims_terminated_total', rollup='delta').sum(by=['${local.cluster}', 'nodepool']).publish('Terminated')"
    }
    disrupted = {
      name    = "NodeClaims disrupted by reason"
      program = "data('karpenter_nodeclaims_disrupted_total', rollup='delta').sum(by=['${local.cluster}', 'reason']).publish('Disrupted')"
    }
    interruptions = {
      name    = "Interruption messages (spot / rebalance / health)"
      program = "data('karpenter_interruption_received_messages_total', rollup='delta').sum(by=['${local.cluster}', 'message_type']).publish('Messages')"
    }
  }
}

resource "signalfx_time_chart" "overview" {
  for_each     = local.overview_charts
  name         = each.value.name
  program_text = each.value.program
  plot_type    = "LineChart"
  time_range   = 3600 * 3
}

resource "signalfx_dashboard" "overview" {
  name            = "Karpenter Overview"
  dashboard_group = signalfx_dashboard_group.karpenter.id
  time_range      = "-3h"

  variable {
    property       = local.cluster
    alias          = "Cluster"
    values         = []
    value_required = false
  }

  grid {
    chart_ids = [
      signalfx_single_value_chart.nodes.id,
      signalfx_single_value_chart.synced.id,
      signalfx_single_value_chart.sli.id,
    ]
    width  = 4
    height = 1
  }

  grid {
    chart_ids = [for k in keys(local.overview_charts) : signalfx_time_chart.overview[k].id]
    width     = 6
    height    = 1
  }
}

# ---------------- Capacity & Disruption ----------------

resource "signalfx_time_chart" "capacity" {
  for_each     = local.capacity_charts
  name         = each.value.name
  program_text = each.value.program
  plot_type    = "ColumnChart"
  stacked      = true
  time_range   = 3600 * 6
}

resource "signalfx_list_chart" "nodepool_limits" {
  name          = "NodePool usage % of limit"
  program_text  = <<-EOF
    U = data('karpenter_nodepools_usage').sum(by=['${local.cluster}', 'nodepool', 'resource_type'])
    L = data('karpenter_nodepools_limit').sum(by=['${local.cluster}', 'nodepool', 'resource_type'])
    (U / L * 100).publish('% of limit')
  EOF
  sort_by       = "-value"
  max_precision = 3
}

resource "signalfx_dashboard" "capacity" {
  name            = "Karpenter Capacity & Disruption"
  dashboard_group = signalfx_dashboard_group.karpenter.id
  time_range      = "-6h"

  variable {
    property       = local.cluster
    alias          = "Cluster"
    values         = []
    value_required = false
  }

  grid {
    chart_ids = concat(
      [signalfx_list_chart.nodepool_limits.id],
      [for k in keys(local.capacity_charts) : signalfx_time_chart.capacity[k].id],
    )
    width  = 6
    height = 1
  }
}
