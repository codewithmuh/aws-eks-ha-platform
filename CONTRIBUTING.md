# Contributing

This is a teaching / portfolio project for the [devopsbymuh](https://youtube.com/@devopsbymuh)
YouTube channel. Issues and PRs that improve clarity, fix bugs, or tighten the
production practices are very welcome.

## Ground rules

- **Keep the app boring.** The services are deliberately small — the value is the
  infrastructure around them. Don't add app features that don't serve a DevOps lesson.
- **Config comes from the environment.** No hard-coded endpoints or secrets. The same
  image must run against a local container, an in-cluster store, or a managed AWS service.
- **Security defaults stay on.** Non-root containers, fail-closed readiness, least-privilege
  IAM. If a change relaxes one, say why in the PR.

## Local dev

```bash
make up        # build + run the whole stack on Docker Compose
make smoke     # end-to-end smoke test
make fencing-demo   # kill the leader, watch failover + fencing
make down      # stop
```

## Before opening a PR

- `make smoke` passes against the local stack.
- `terraform fmt` and `terraform validate` are clean under `infra/` if you touched IaC.
- `helm lint charts/*` is clean if you touched charts.
