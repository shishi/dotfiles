# nyah
set -x OS_USERNAME shishi
set -x OS_PASSWORD nyahpassword
set -x OS_TENANT_NAME minne
set -x OS_AUTH_URL https://nyah.pepabo.com/mitaka/auth/v3/
set -x OS_IDENTITY_API_VERSION 3
set -x OS_USER_DOMAIN_NAME Default
set -x OS_PROJECT_DOMAIN_NAME Default
set -x OS_CERT ~/.kagiana/nyah.pepabo.com.cert
set -x OS_KEY ~/.kagiana/nyah.pepabo.com.key
set -x OS_CACERT ~/.kagiana/nyah.pepabo.com.ca

function nyah_consul
  set -l token (cat ~/.kagiana/token)
  VAULT_TOKEN=$token consul-template -config=/home/shishi/dev/src/git.pepabo.com/tech/kagiana/consul-template/my-config.hcl
end
