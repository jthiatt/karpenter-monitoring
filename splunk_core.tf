# Log-based alerts and dashboard in Splunk Core (Karpenter logs are JSON: level, message, controller, NodeClaim, NodePool, error).

locals {
  log_alerts = {
    error_spike = {
      name     = "Karpenter - error log spike"
      search   = "${local.log_search} | search level=ERROR | stats count by k8s.cluster.name | where count > 50"
      earliest = "-15m"
    }
    launch_failures = {
      name     = "Karpenter - NodeClaim launch failures"
      search   = "${local.log_search} | search level=ERROR \"launching nodeclaim\" | stats count values(error) as errors by k8s.cluster.name | where count > 5"
      earliest = "-15m"
    }
    crash = {
      name     = "Karpenter - panic or leader election lost"
      search   = "${local.log_search} \"panic\" OR \"leader election lost\" | stats count by k8s.cluster.name, k8s.pod.name"
      earliest = "-10m"
    }
  }
}

resource "splunk_saved_searches" "karpenter" {
  for_each = local.log_alerts

  name                   = each.value.name
  search                 = each.value.search
  is_scheduled           = true
  cron_schedule          = "*/5 * * * *"
  dispatch_earliest_time = each.value.earliest
  dispatch_latest_time   = "now"

  alert_type            = "number of events"
  alert_comparator      = "greater than"
  alert_threshold       = "0"
  alert_digest_mode     = true
  alert_track           = true
  alert_suppress        = true
  alert_suppress_period = "30m"

  actions                   = "email"
  action_email_to           = var.alert_email
  action_email_subject      = "Splunk Alert: $name$"
  action_email_send_results = true

  acl {
    app     = "search"
    owner   = "nobody"
    sharing = "app"
  }
}

resource "splunk_data_ui_views" "karpenter" {
  name     = "karpenter_logs"
  eai_data = <<-EOF
    <form version="1.1" theme="dark">
      <label>Karpenter Logs</label>
      <fieldset submitButton="false">
        <input type="time" token="t"><label>Time</label><default><earliest>-4h</earliest><latest>now</latest></default></input>
        <input type="text" token="cluster"><label>Cluster</label><default>*</default></input>
      </fieldset>
      <row>
        <panel><title>Log volume by level</title><chart>
          <search><query><![CDATA[${local.log_search} | search k8s.cluster.name="$cluster$" | timechart count by level]]></query><earliest>$t.earliest$</earliest><latest>$t.latest$</latest></search>
          <option name="charting.chart">column</option><option name="charting.chart.stackMode">stacked</option>
        </chart></panel>
        <panel><title>Errors by controller</title><chart>
          <search><query><![CDATA[${local.log_search} | search k8s.cluster.name="$cluster$" level=ERROR | timechart count by controller]]></query><earliest>$t.earliest$</earliest><latest>$t.latest$</latest></search>
          <option name="charting.chart">line</option>
        </chart></panel>
      </row>
      <row>
        <panel><title>Launched / registered / deleted NodeClaims</title><chart>
          <search><query><![CDATA[${local.log_search} | search k8s.cluster.name="$cluster$" message IN ("launched nodeclaim", "registered nodeclaim", "initialized nodeclaim", "deleted nodeclaim") | timechart count by message]]></query><earliest>$t.earliest$</earliest><latest>$t.latest$</latest></search>
          <option name="charting.chart">column</option>
        </chart></panel>
        <panel><title>Disruption decisions</title><chart>
          <search><query><![CDATA[${local.log_search} | search k8s.cluster.name="$cluster$" "disrupting node" OR "disrupting nodeclaim" | rex field=message "via (?<method>\w+)" | timechart count by method]]></query><earliest>$t.earliest$</earliest><latest>$t.latest$</latest></search>
          <option name="charting.chart">column</option>
        </chart></panel>
      </row>
      <row>
        <panel><title>Top errors</title><table>
          <search><query><![CDATA[${local.log_search} | search k8s.cluster.name="$cluster$" level=ERROR | stats count latest(_time) as last_seen by k8s.cluster.name, controller, message, error | sort - count | convert ctime(last_seen)]]></query><earliest>$t.earliest$</earliest><latest>$t.latest$</latest></search>
        </table></panel>
      </row>
      <row>
        <panel><title>Insufficient capacity / throttling (EC2)</title><table>
          <search><query><![CDATA[${local.log_search} | search k8s.cluster.name="$cluster$" "InsufficientInstanceCapacity" OR "UnfulfillableCapacity" OR "RequestLimitExceeded" OR "Throttling" | stats count by k8s.cluster.name, NodePool.name, error | sort - count]]></query><earliest>$t.earliest$</earliest><latest>$t.latest$</latest></search>
        </table></panel>
      </row>
    </form>
  EOF

  acl {
    app     = "search"
    owner   = "nobody"
    sharing = "app"
  }
}
