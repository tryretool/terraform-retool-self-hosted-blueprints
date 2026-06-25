# from v0.3.0
moved {
  from = helm_release.external_secrets
  to   = helm_release.external_secrets[0]
}

# from v0.3.0
moved {
  from = helm_release.reloader
  to   = helm_release.reloader[0]
}

# from v0.3.0
moved {
  from = kubectl_manifest.external_secret_extra_env_vars
  to   = kubectl_manifest.external_secret_extra_env_vars[0]
}
