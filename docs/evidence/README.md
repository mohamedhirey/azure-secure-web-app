# Deployment evidence

This web app and everything under it was deployed to a real Azure subscription, verified and removed again on **19 November 2026 (UTC)**. Everything in this folder was captured during that session. It describes release [`v1.0.0`](https://github.com/mohamedhirey/azure-secure-web-app/releases/tag/v1.0.0).

Subscription, tenant and identity IDs, the random suffix in resource names, public addresses and the alert email address are redacted. Long Terraform output is condensed to the lines that carry the result. Nothing is altered.

It ran in **West US 3**, not the project's default of Canada Central. The subscription is a free trial, and Azure would not let it create a Cosmos DB account in either Canadian region. `GUIDE.md` covers that case, and [`02-plan-and-apply.txt`](02-plan-and-apply.txt) has the detail. The `cac` in the resource names is the project's naming default, not the region.

## What each file proves

| Claim | Proof |
|---|---|
| The security settings are tested, and the test can fail | [`01-unit-tests.txt`](01-unit-tests.txt): 4 pass. With Cosmos DB opened to the public network, 1 fails with the message written for it. Restored, 4 pass. |
| The plan was read before anything was applied | [`02-plan-and-apply.txt`](02-plan-and-apply.txt): 32 to add, no public IP, both data services private in the plan. Then the apply, and what existed afterwards. |
| The app works with no credential anywhere | [`03-app-works.txt`](03-app-works.txt): the counter rises, so the app read and wrote Cosmos DB as its managed identity. `secret_from_key_vault` is `true`, so the platform fetched the secret the same way. |
| The app's identity can do two things and nothing else | [`04-identity-and-least-privilege.txt`](04-identity-and-least-privilege.txt): `Key Vault Secrets User` on one vault. The Cosmos DB data role on one database, not the account. |
| The data tier has no public path | [`05-data-tier-private.txt`](05-data-tier-private.txt): Key Vault answers `ForbiddenByConnection`. Cosmos DB, given a valid Entra ID token from the internet, answers `403`, blocked by the account firewall. |
| Every request and every vault access is logged | [`06-logs-and-traces.txt`](06-logs-and-traces.txt): HTTP logs, the Key Vault audit log, and the traces the app sent to Application Insights. |
| The alert has been seen firing | [`07-alert-fired.txt`](07-alert-fired.txt): 12 deliberate errors at 02:58. Fired at 03:01. Resolved on its own at 03:08. |
| Nothing was left behind | [`08-teardown.txt`](08-teardown.txt): the first `terraform destroy` failed, which is recorded along with the fix and the run that proves the fix. Afterwards the whole subscription held 0 resource groups, 0 resources, and nothing soft-deleted. |

## The audit log, in four rows

From [`06-logs-and-traces.txt`](06-logs-and-traces.txt). The app's identity is refused when its request arrives from a public address, and allowed when it arrives over the private endpoint. The subscription owner is then refused twice: first by RBAC and, once granted the role, by the network.

```text
Time (UTC)  Operation  Result     Caller address           Caller               Reason
02:48:56    SecretGet  Forbidden  <app-service-public-ip>  app identity         Public network access is disabled
02:49:28    SecretGet  OK         10.60.1.254              app identity
02:59:08    SecretGet  Forbidden  <public address>         subscription owner   Caller is not authorized
03:00:24    SecretGet  Forbidden  <public address>         owner, role granted  Public network access is disabled
```

## What deploying it for real found

Offline validation and the unit tests passed before any of this. These only showed up against live services.

1. **Region and quota are per subscription.** The free trial had no Cosmos DB access in Canada, and the App Service quota API reported zero instances in every region that publishes a figure. West US 3 allowed both. The App Service plan was created first as a one-minute probe, so a bad region would fail early and not ten minutes into an apply. The guide now has both checks.
2. **"Refused" is not one thing.** The guide said the owner's attempt to read the secret would be refused because the network is private. It was refused, but by RBAC: Owner is a control-plane role. The network refusal only appears once the role is granted. Step 13 now does both, in that order.
3. **Cosmos DB answers 401 before it answers 403.** An unauthenticated request to the public endpoint gets `401`, which proves nothing about the network. Only a request carrying a valid token reaches the firewall and gets `403`.
4. **The deploy command's verdict was wrong.** `az webapp deploy` gave up after ten minutes and reported that the site had failed to start, while the app had been serving for nine of them. The platform's own record shows the deployment complete and the instance started. [`03-app-works.txt`](03-app-works.txt) records the failure message as it happened, next to what the platform says.
5. **`terraform destroy` did not work.** This is the one that mattered. The secret was a managed resource, Resource Manager has no DELETE for a Key Vault secret, and the destroy stopped at `405 DeleteNotSupported` with the vault still standing. The secret is now written by an action, which leaves nothing to delete. The fix was then proven on Azure: create the vault and the secret again, destroy in one pass. [`08-teardown.txt`](08-teardown.txt) has all of it.
6. **"Deleted" is not always gone.** A check across the whole subscription, not just the one resource group, found the Log Analytics workspace only soft-deleted, recoverable for 14 days with its logs, and a `NetworkWatcherRG` that Azure had created by itself. The workspace is now deleted permanently on destroy, and the guide's teardown step checks for both.

## Not in this folder

The Application Insights application map and the alert email are a portal view and an inbox. [`06-logs-and-traces.txt`](06-logs-and-traces.txt) and [`07-alert-fired.txt`](07-alert-fired.txt) hold the same information as query output from Azure.

## One thing still open

`ci.yml` pins `actions/checkout@v4`, `hashicorp/setup-terraform@v3` and `terraform-linters/setup-tflint@v4`. These target Node.js 20, which GitHub now forces onto Node.js 24 with a warning on every run. They work. Moving to the current majors is a small follow-up.
