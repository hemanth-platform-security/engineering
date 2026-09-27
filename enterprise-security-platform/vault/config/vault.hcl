# Local learning configuration only. Do not expose this listener to a network.
disable_mlock = true
ui            = true
api_addr      = "http://0.0.0.0:8200"
log_level     = "info"

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

storage "file" {
  path = "./data"
}
