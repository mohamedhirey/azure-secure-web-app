# Deployment guide — Azure Secure Web App

This is the procedure that produced the deployment recorded in [`docs/evidence/`](docs/evidence/README.md). It takes the repository from a clean clone to a running, verified application and back to an empty subscription.

Every step ends with a **Done when** check. A step is not complete until its check is true.

| Phase | Steps | What happens |
|---|---|---|
| **Prerequisites** | 1–3 | Tools, sign-in, resource providers, budget alert |
| **Repository and offline validation** | 4–8 | Repository, design review, validation, unit tests, CI |
| **Deploy, verify, tear down** | 9–18 | Plan, apply, deploy the code, verify, alert drill, evidence, teardown |

**Ground rules:**

1. Nothing is created in Azure before Step 10. Everything earlier is offline or account setup.
2. Teardown is part of the deployment. Steps 9 to 18 are done in one sitting. Unlike the landing zone, this deployment costs money while it exists: about $30 a month if it is left running.
3. The repository is public from the first commit. A `.tfvars` file or a state file is never committed. The state file contains the demo secret.

## Checklist

**Prerequisites**
- [ ] 1 — Tools installed
- [ ] 2 — Signed in, providers registered
- [ ] 3 — Budget alert set

**Repository and offline validation**
- [ ] 4 — Repository created
- [ ] 5 — Design reviewed against the code
- [ ] 6 — Offline validation passes
- [ ] 7 — Unit tests pass and have been seen to fail
- [ ] 8 — First commit pushed, CI green

**Deploy, verify, tear down**
- [ ] 9 — Plan shows 32 to add
- [ ] 10 — Apply complete
- [ ] 11 — Application code deployed
- [ ] 12 — Application works: counter rises, secret resolved
- [ ] 13 — Data tier proven private
- [ ] 14 — Logs and traces confirmed
- [ ] 15 — Alert fired
- [ ] 16 — Evidence captured
- [ ] 17 — Everything torn down
- [ ] 18 — Deployment recorded

---

## Prerequisites

### Step 1 — Install the tools

Required: **Terraform**, **TFLint**, **Azure CLI**, **GitHub CLI**, **Git**, `zip` and `curl`.

```bash
terraform version
tflint --version
az version
gh --version
git --version
zip --version | head -1
```

On Debian, Ubuntu and Mint, `scripts/setup-linux.sh` in the [companion repository](https://github.com/mohamedhirey/azure-hub-spoke-landing-zone) installs the first five. `zip` is `sudo apt install zip`.

**Done when** all six commands print a version.

---

### Step 2 — Sign in and register providers

```bash
az login
az account set --subscription "<subscription-id>"
az account show --output table
gh auth status
```

The signed-in account needs the **Owner** role on the subscription, because this deployment creates role assignments.

Register the resource providers this deployment uses. Without this, Step 10 fails with `MissingSubscriptionRegistration`:

```bash
for ns in Microsoft.Network Microsoft.Web Microsoft.DocumentDB Microsoft.KeyVault \
          Microsoft.ManagedIdentity Microsoft.OperationalInsights Microsoft.Insights \
          Microsoft.AlertsManagement; do
  az provider register --namespace "$ns"
done
```

Registration takes a few minutes. Check it:

```bash
az provider list --query "[?registrationState=='Registering'].namespace" -o tsv
```

**Done when** `az account show` prints the intended subscription, `gh auth status` shows a signed-in account, and the last command prints nothing.

---

### Step 3 — Set a budget alert

Portal → **Cost Management + Billing → Budgets → Add**. Amount **$10**, alerts at **50%** and **90%**, sent to a monitored address.

One full run of this guide costs well under a dollar. If the budget ever fires, something was left running: go to Step 17.

**Done when** the budget exists with a recipient.

---

## Repository and offline validation

### Step 4 — Create the repository

From the repository root:

```bash
git init -b main
gh repo create azure-secure-web-app --public --source=. --remote=origin
```

Confirm the ignore rules are in effect before anything is committed:

```bash
git status --porcelain | grep -E '\.tfvars$|\.tfstate' || echo "clean - no secrets staged"
```

**Done when** that prints `clean - no secrets staged`.

---

### Step 5 — Review the design before deploying

Each file carries one or two design decisions. Confirm the code does what this table says before running any of it. The reasoning is in a comment next to the code, and again in the decisions table in [`README.md`](README.md).

| File | What to confirm |
|---|---|
| `infra/network.tf` | The web app is not placed in `snet-app`. The subnet is delegated to App Service and carries only the app's outbound traffic (VNet integration), which is how the app reaches the private endpoints. |
| `infra/network.tf` | Each private endpoint has a private DNS zone linked to the VNet. Inside the network the service's normal hostname resolves to the private address, so the app needs no special connection string. |
| `infra/network.tf` | `snet-pe` sets `private_endpoint_network_policies = "Enabled"`. Without it, NSG rules are not applied to private endpoints. |
| `infra/data.tf` | Cosmos DB sets `public_network_access_enabled = false` and `local_authentication_enabled = false`: no internet path, and account keys are refused. |
| `infra/data.tf` | The secret is written through Azure Resource Manager, the control plane. Terraform never connects to the vault, so the vault needs no firewall exception. |
| `infra/identity.tf` | The identity is user-assigned and created before the app, so both role assignments exist by the time the app first starts. |
| `infra/app.tf` | `DEMO_API_KEY` is a Key Vault reference. The platform fetches the secret with the app's identity, and the value appears in no app setting, file or pipeline. |
| `app/app.py` | The app connects to Cosmos DB with `ManagedIdentityCredential`: a short-lived token, no key and no password. |

**Done when** the code matches every row.

---

### Step 6 — Validate offline

Nothing here contacts Azure; `-backend=false` is what guarantees that.

```bash
terraform fmt -check -recursive
(cd infra && terraform init -backend=false && terraform validate)
```

Then lint:

```bash
tflint --init
tflint --recursive
```

**Done when** `validate` prints `Success!` and tflint prints nothing.

---

### Step 7 — Run the unit tests, and prove they can fail

```bash
cd infra
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
terraform test
```

Expect `Success! 4 passed, 0 failed.`

> `terraform test` needs the `az login` session, because the provider signs in during plan. It still creates nothing: `command = plan` asserts against the plan only.

A test that has never been seen failing is not a test that can be trusted. In `infra/data.tf`, change the Cosmos DB line `public_network_access_enabled = false` to `true` and run `terraform test` again. The first test must fail with the message written in `tests/posture.tftest.hcl`. Restore the value and confirm 4 pass.

```bash
cd ..
```

**Done when** 4 tests pass, and one has been seen failing.

---

### Step 8 — First commit, and CI

```bash
git add .
git commit -m "feat: secure web app infrastructure, app and unit tests"
git push -u origin main
gh run watch
```

`.github/workflows/ci.yml` has no Azure credentials of any kind. Checking the code does not need cloud access, so it gets none.

**Done when:**
- [ ] The **Validate** run is green
- [ ] The repository is reachable without signing in
- [ ] No `.tfvars` or state file is committed
- [ ] Nothing exists in Azure

---

## Deploy, verify, tear down

Run Steps 9 to 17 in one shell session, inside `infra/`. Later steps reuse the variables set in Step 10.

If the deployment cannot be completed, go to Step 17 and remove what exists. A complete repository with nothing deployed is a fine outcome. Resources left running and forgotten are not.

---

### Step 9 — Plan, and read the plan

```bash
az login
az account set --subscription "<subscription-id>"

cd infra
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)

cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set alert_email to a monitored inbox
```

The default region is Canada Central. Not every subscription may create every service in every region, and new or free-trial subscriptions are the most restricted. Check before applying, and set `location` in `terraform.tfvars` if the answer is `false`:

```bash
az cosmosdb locations show --location canadacentral \
  --query properties.isSubscriptionRegionAccessAllowedForRegular
```

Then plan:

```bash
terraform init
terraform plan
```

Expect **32 to add**. Read the plan and confirm three things:

1. `azurerm_cosmosdb_account` shows `public_network_access_enabled = false` and `local_authentication_enabled = false`.
2. `azurerm_key_vault` shows `public_network_access_enabled = false`.
3. No resource is a public IP address, and no app setting contains a key or connection string to the database.

**Done when** the plan shows 32 to add, 0 to change, 0 to destroy, and all three points are confirmed.

---

### Step 10 — Apply

```bash
terraform apply
```

Type `yes`. This takes about twenty minutes. The Cosmos DB account and its private endpoint are the slow parts.

While it runs, Azure Monitor emails the alert address to say it was added to an action group. That is the alert wiring, working.

Then capture the names every later step needs:

```bash
RG=$(terraform output -raw resource_group_name)
APP=$(terraform output -raw web_app_name)
URL=$(terraform output -raw web_app_url)
COSMOS=$(terraform output -raw cosmos_account_name)
KV=$(terraform output -raw key_vault_name)
WS=$(terraform output -raw log_analytics_workspace_guid)
SUBID=$(az account show --query id -o tsv)

echo "$RG | $APP | $URL | $COSMOS | $KV | $WS"
```

**Done when** apply reports `32 added` and the `echo` prints six values, none empty.

---

### Step 11 — Deploy the application code

At this point Azure has an empty web app. Package the code and push it:

```bash
(cd ../app && zip -r ../app.zip . -x '__pycache__/*')

az webapp deploy --resource-group "$RG" --name "$APP" --src-path ../app.zip --type zip
```

The deployment authenticates with the Entra ID session. The web app has no publishing password to steal. Azure installs `requirements.txt` on its side, which takes a few minutes.

**Done when** the command ends with a success message and this prints `ok`:

```bash
curl -s "$URL/health"
```

If the command gives up after ten minutes while that `curl` prints `ok`, the code is deployed and running. See **Troubleshooting**.

---

### Step 12 — Confirm the application works

```bash
curl -s "$URL/"
curl -s "$URL/"
```

Expect JSON like `{"secret_from_key_vault":true,"visits":2}`, with `visits` one higher each time.

Those two fields are the whole design, proven end to end:

- **`visits` rising** means the app reached Cosmos DB through the private endpoint, signed in as its managed identity, and both read and wrote an item, with no key anywhere.
- **`secret_from_key_vault: true`** means the platform fetched the secret from Key Vault through the private endpoint, using that same identity.

The first request can take 20 seconds while the app warms up. A `500` in the first minute or two is role and DNS propagation: wait and retry. If `secret_from_key_vault` is `false`, run `az webapp restart -g "$RG" -n "$APP"` and try again. References resolve when the app starts.

**Done when** `visits` increases and `secret_from_key_vault` is `true`.

---

### Step 13 — Prove the data tier is private

Terraform reporting success is not evidence. Ask Azure.

```bash
# 1. The settings, read back from the live resources
az cosmosdb show -g "$RG" -n "$COSMOS" \
  --query "{PublicAccess:publicNetworkAccess, KeysDisabled:disableLocalAuth}" -o table

az keyvault show -n "$KV" \
  --query "properties.{PublicAccess:publicNetworkAccess, RbacOnly:enableRbacAuthorization}" -o table

# 2. Both private endpoints are connected
az network private-endpoint list -g "$RG" \
  --query "[].{Name:name, State:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status}" -o table

# 3. The app has no public-facing database credential
az webapp config appsettings list -g "$RG" -n "$APP" --query "[].name" -o tsv
```

Confirm: public access `Disabled` on both, keys disabled `True`, RBAC `True`, both endpoints `Approved`, and no setting name that is a key or connection string to Cosmos DB.

**Then test it from outside.** Signed in as the subscription owner, on a machine that is not in the virtual network, read the secret:

```bash
az keyvault secret show --vault-name "$KV" --name demo-api-key
```

It fails with `Forbidden`, but the reason matters: `Caller is not authorized`. That is RBAC, not the network. Owner is a control-plane role. It can delete the vault and still cannot read a secret inside it. A good result, but not the one this step is after.

Take RBAC out of the picture. Grant the signed-in account the same role the app holds, wait a minute, and try again:

```bash
ME=$(az ad signed-in-user show --query id -o tsv)
KVID=$(az keyvault show -n "$KV" --query id -o tsv)

az role assignment create --assignee-object-id "$ME" --assignee-principal-type User \
  --role "Key Vault Secrets User" --scope "$KVID"

az keyvault secret show --vault-name "$KV" --name demo-api-key
```

Now it must fail with `Public network access is disabled`, inner error `ForbiddenByConnection`. The permission is in place and the request still never reaches the secret, because it did not come from inside the virtual network. That refusal is the proof.

Remove the role again:

```bash
az role assignment delete --assignee "$ME" --role "Key Vault Secrets User" --scope "$KVID"
```

The same test against Cosmos DB needs a token. An unauthenticated request is answered `401` before the firewall is consulted, which proves nothing about the network. A request carrying a valid Entra ID token must be answered `403`, blocked by the account firewall:

```bash
TOKEN=$(az account get-access-token --resource https://cosmos.azure.com --query accessToken -o tsv)
AUTH=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote('type=aad&ver=1.0&sig='+sys.argv[1], safe=''))" "$TOKEN")

curl -s -w "\nHTTP %{http_code}\n" \
  -H "Authorization: $AUTH" -H "x-ms-version: 2018-12-31" \
  -H "x-ms-date: $(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S GMT')" \
  -H 'x-ms-documentdb-partitionkey: ["counter"]' \
  "https://$COSMOS.documents.azure.com/dbs/appdb/colls/visits/docs/counter"
```

**Done when** all the settings match, the vault refuses with `ForbiddenByConnection`, and Cosmos DB answers `403`.

---

### Step 14 — Confirm the logs and traces

Logs take 5 to 15 minutes to arrive. Generate some traffic, then wait:

```bash
for i in $(seq 10); do curl -s -o /dev/null "$URL/"; done
```

Every HTTP request to the app (the CLI may offer to install the `log-analytics` extension):

```bash
az monitor log-analytics query -w "$WS" -o table --analytics-query \
  "AppServiceHTTPLogs | project TimeGenerated, CsMethod, CsUriStem, ScStatus | order by TimeGenerated desc | take 10"
```

Every access to the vault:

```bash
az monitor log-analytics query -w "$WS" -o table --analytics-query \
  "AzureDiagnostics | where ResourceProvider == 'MICROSOFT.KEYVAULT' | project TimeGenerated, OperationName, ResultSignature, CallerIPAddress | order by TimeGenerated desc | take 10"
```

Look for a `SecretGet`, which is the app's identity fetching the secret, and for the refused attempts from Step 13.

Look at `CallerIPAddress` as well. The app's own identity may appear refused from a public address moments before it succeeds from `10.60.1.x`. The platform's first attempt to resolve the reference left by the public route, and the vault turned it away. Same identity, same secret, different network path: that is the design working.

Then in the portal: **Application Insights → appi-webapp-cac-001 → Application map**. It draws the web app and its calls to Cosmos DB, with response times, from the traces the app sends.

**Done when** both queries return rows and the application map shows the app calling Cosmos DB.

---

### Step 15 — Make the alert fire

The alert triggers on more than five server errors in five minutes. The app's `/fail` endpoint returns an error on purpose:

```bash
for i in $(seq 12); do curl -s -o /dev/null -w "%{http_code}\n" "$URL/fail"; done
```

Twelve lines of `500`. Within about five minutes the alert fires, and the alert address receives **Fired: Sev2 Azure Monitor Alert alert-webapp-http5xx**. Confirm it from Azure:

```bash
az rest --method get \
  --url "/subscriptions/$SUBID/providers/Microsoft.AlertsManagement/alerts?api-version=2019-05-05-preview&targetResourceGroup=$RG" \
  --query "value[].properties.essentials.{Condition:monitorCondition, Severity:severity, Fired:startDateTime, Resolved:monitorConditionResolvedDateTime}" -o table
```

A few minutes after the errors stop, the same query shows it `Resolved`.

An alert that has never been seen firing is not an alert that can be trusted.

**Done when** Azure Monitor shows the alert as `Fired`.

---

### Step 16 — Capture evidence

Save the output of Steps 9 to 15 to `../docs/evidence/`: the plan and apply, the application's responses, the settings and refusals from Step 13, the log queries, and the alert's fired and resolved times.

Redact the subscription ID, tenant ID, identity object IDs, the resource name suffix, public addresses and the alert address before committing anything. Edit nothing else.

**Done when** the captured output is in `docs/evidence/`, redacted.

---

### Step 17 — Tear down

```bash
terraform destroy
```

Type `yes`. This takes about fifteen minutes; the Cosmos DB account is the slow part. It must finish with `Destroy complete!` in a single run. Then verify from Azure:

```bash
az group exists --name "$RG"                              # expect: false
az keyvault list-deleted --query "[].name" -o tsv         # expect: nothing starting kv-webapp-

az rest --method get \
  --url "/subscriptions/$SUBID/providers/Microsoft.OperationalInsights/deletedWorkspaces?api-version=2023-09-01" \
  --query "value[].name" -o tsv                           # expect: nothing
```

"Deleted" is not always gone. Key Vault and Log Analytics both keep a deleted resource recoverable for a while, data included. The provider settings in `infra/versions.tf` purge both, and these checks prove it. If a vault is still listed, remove it by hand:

```bash
az keyvault purge --name "$KV"
```

Look across the whole subscription as well, not only at this deployment's resource group:

```bash
az group list --query "[].name" -o tsv
```

Azure creates a `NetworkWatcherRG` group by itself the first time a virtual network appears in a region. It is free and it is not part of this deployment. To leave the subscription empty: `az group delete --name NetworkWatcherRG --yes`.

Remove the local build output. The state file held the demo secret. With the vault gone it is worthless, but remove it anyway:

```bash
cd ..
rm -f app.zip infra/terraform.tfstate infra/terraform.tfstate.backup
```

**Done when:**
- [ ] `terraform destroy` ended with `Destroy complete!`
- [ ] `az group exists` prints `false`
- [ ] No deleted `kv-webapp-*` vault and no deleted workspace is listed
- [ ] No state file remains in `infra/`

---

### Step 18 — Record the deployment

Update the **Evidence status** line in `README.md`:

> Deployed and verified on `<date>`, then removed. No Azure resource remains.

```bash
git status --porcelain | grep -E '\.tfvars$|\.tfstate' || echo "clean - no secrets staged"
git add .
git commit -m "docs: deployment evidence and verified teardown"
git push
```

Then, 48 hours later, check the charges:

```bash
az consumption usage list --output table
```

Expect well under a dollar for one run.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `MissingSubscriptionRegistration` | A resource provider is not registered | Step 2 |
| `AuthorizationFailed` on a role assignment | Creating role assignments needs Owner or User Access Administrator | Use an account that holds one of those roles |
| App Service plan fails with a quota error (`Current Limit ... 0`) | Some new subscriptions have no App Service quota in some regions | Set `location` to another region in `terraform.tfvars`, destroy, apply again |
| Cosmos DB fails with `ServiceUnavailable` and "high demand" | The region is not accepting new accounts for this subscription type | Same fix: change `location`. The check in Step 9 finds this before the apply |
| Not sure a region will grant an App Service plan | Quota differs by region and subscription type | `terraform apply -target=azurerm_service_plan.this` creates only the resource group and the plan, in under a minute. If it works, run the full `terraform apply` |
| `az webapp deploy` gives up with `site failed to start within 10 mins`, but `/health` prints `ok` | The command's own tracker did not see the instance report as started. The code is deployed and running | Confirm with `az webapp log deployment list -g "$RG" -n "$APP"` (status `4`, complete) and `az webapp troubleshoot status -g "$RG" -n "$APP"` (state `Started`), then carry on |
| `terraform test` fails to authenticate | The provider signs in during plan | `az login`, then export `ARM_SUBSCRIPTION_ID` |
| `subscription ID could not be determined` | `ARM_SUBSCRIPTION_ID` is not set in this shell | Re-run the `export` from Step 9 |
| `$URL` shows a default Azure page | The code is not deployed yet, or the build is still running | Step 11, then wait a few minutes |
| `/` returns `500` | Role or DNS propagation, in the first minutes | Wait and retry. `az webapp log tail -g "$RG" -n "$APP"` shows the error |
| `secret_from_key_vault` is `false` | The reference was resolved before the role assignment propagated | `az webapp restart -g "$RG" -n "$APP"` |
| `az webapp deploy` is rejected with 401 or 403 | An old Azure CLI that still expects a publishing password | `az upgrade` |
| Log queries return nothing | Ingestion lag | Wait 15 minutes |
| No alert email | The first email asked for confirmation, or it went to spam | Check spam. The query in Step 15 shows whether the alert fired |
| `$RG` and the other variables are empty | Shell variables do not survive a new terminal | Re-run the variable block from Step 10 inside `infra/` |

## Extending this

In rough order of value:

1. **Deploy from the pipeline.** Publish the application from GitHub Actions with OIDC, reusing the pattern in the landing zone repository, instead of from a workstation.
2. **Scan in CI.** Add a Trivy IaC scan to `ci.yml`.
3. **Availability test.** Call `/health` every five minutes and alert when it fails.
4. **Join the landing zone.** Peer this virtual network to the landing zone's hub and move the private DNS zones there.
