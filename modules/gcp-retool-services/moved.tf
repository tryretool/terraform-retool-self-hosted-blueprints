# from v0.3.0: the ExternalSecret manifests are now rendered through the local
# passthrough chart as a single release rather than one resource per secret.
moved {
  from = helm_release.external_secret_crs
  to   = helm_release.external_secret_crs[0]
}
