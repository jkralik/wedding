# Wedding web

Jednoducha svadobna stranka, kde:

- hore je fotka manzelov (`Oznamko Petra & Jozef.svg`, mozes nahradit vlastnou fotkou)
- obsah sa nacitava zo suboru `content.md` a renderuje ako HTML

## Lokalny test

Ak mas Python:

```bash
python3 -m http.server 8080
```

Potom otvor `http://localhost:8080`.

## Docker build a push

```bash
docker build -t ghcr.io/jkralik/wedding:latest .
docker push ghcr.io/jkralik/wedding:latest
```

Ak pouzijes iny registry/image tag, uprav `k8s/deployment.yaml`.

## Automaticky push image cez GitHub Actions

Workflow je v subore [`.github/workflows/docker-publish.yml`](.github/workflows/docker-publish.yml).

Publikovanie prebehne automaticky:

- pri pushi do branchu `main`
- pri pushi tagu `v*`
- alebo manualne cez `workflow_dispatch`

Image sa publikuje do GHCR pod:

- `ghcr.io/<owner>/<repo>:latest` (default branch)
- `ghcr.io/<owner>/<repo>:<sha>`
- `ghcr.io/<owner>/<repo>:<branch|tag>`

## Lokalny deploy do Kubernetes

Script `deploy-local-k8s.sh`:

- postavi Docker image
- pri `kind`/`k3d`/`minikube`/`microk8s` ho nahra do lokalneho klastra
- aplikuje namespace + deployment + service

Spustenie:

```bash
./deploy-local-k8s.sh
```

Default je `--with-ingress --with-tls`.

Volitelne:

```bash
./deploy-local-k8s.sh --with-ingress
./deploy-local-k8s.sh --with-tls
```

Poznamka pre microk8s:

```bash
microk8s enable dns
microk8s enable ingress
microk8s enable cert-manager
```

## K8s deploy s HTTPS cez ACME

Predpoklady:

- v clustri je nainstalovany Ingress controller (`nginx`)
- v clustri je nainstalovany `cert-manager`
- DNS `A`/`AAAA` zaznamy pre `petra-jozef.eu` a `www.petra-jozef.eu` smeruju na ingress load balancer

Deploy:

```bash
kubectl apply -k k8s
```

Kontrola certifikatu:

```bash
kubectl -n wedding get certificate
kubectl -n wedding describe certificate petra-jozef-eu-tls
kubectl -n wedding get ingress
```

Po uspesnom vydani certifikatu bude stranka dostupna na:

- https://petra-jozef.eu
- https://www.petra-jozef.eu
