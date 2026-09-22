# Used by Marketplace's terraform plan check. Do not set project_id,
# helm_chart_repo / helm_chart_name / helm_chart_version, or any variable
# declared in schema.yaml — the validator supplies those.
goog_cm_deployment_name = "rtmp-test"
prefix                  = "rtmp"
region                  = "us-central1"
domain_name             = "retool.example.test"
