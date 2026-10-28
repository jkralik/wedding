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

Pre menovky otvor:

```text
http://localhost:8080/menovky/tlac-menovky.html
```

Stranka nacita `menovky/2026-06-11-nasa-svadba - Zoznamy.csv`, zoberie prvy stlpec a vygeneruje A4 strany s dvojstrannymi menovkami z `menovky/menovka.svg`.

## Docker build a push

```bash
docker buildx create --name wedding-multiarch --driver docker-container --use
docker buildx build --platform linux/amd64,linux/arm64 \
  -t ghcr.io/jkralik/wedding:latest --push .
```

Pri dalsom builde pouzi existujuci builder cez `docker buildx use wedding-multiarch`.
Pred pushom sa prihlas do GHCR cez `docker login ghcr.io`.
Oba varianty sa publikuju pod rovnakym tagom; Kubernetes automaticky vyberie
spravnu architekturu. Zakladny `nginx:1.27-alpine` podporuje obe platformy.
Build neobsahuje kroky `RUN`, preto na cross-build netreba lokalne nastavovat QEMU.

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

Kazdy publikovany tag obsahuje `linux/amd64` aj `linux/arm64` (Raspberry Pi 4
so 64-bit OS).

## Lokalny deploy do Kubernetes

Script `deploy-local-k8s.sh`:

- pre defaultny GHCR image pouzije publikovany image bez lokalneho buildu
- pre iny nazov image postavi lokalny Docker image
- pri `kind`/`k3d`/`minikube`/`microk8s` ho nahra do lokalneho klastra
- aplikuje namespace + deployment + service
- ingress a TLS su predvolene zapnute, s ingress triedou `public`
- existujuci spolocny `ClusterIssuer letsencrypt-prod` iba pouziva; nikdy ho nevytvara ani neprepisuje
- pred zmenami overi dostupnost klastra, ingress triedu a Ready issuer s jednym
  HTTP-01 solverom `ingress.class` zhodnym s vybranou triedou, bez `ingress.name`
- pri nevhodnom issueri sa zastavi; jeho opravu musi administrator vykonat samostatne

Spustenie:

```bash
./deploy-local-k8s.sh
```

Default je `--with-ingress --with-tls`.

Bez zmien klastra alebo buildu zobraz vysledne manifesty:

```bash
./deploy-local-k8s.sh --dry-run
```

`--dry-run` iba renderuje manifesty, neoveruje DNS, ACME ani stav issuera.
Pri realnom deployi sa tieto podporovane predpoklady kontroluju pred buildom
a aplikovanim manifestov; klientsky dry-run navyse overi manifesty.
Samotny uspech deployu potvrdzuje rollout aplikacie, nie vydanie certifikatu.

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

## Raspberry Pi 4 + MicroK8s (ARM64)

Pouzi **64-bit Ubuntu Server (arm64)** podporovany tvojou verziou MicroK8s.
32-bit OS (`armv7l`) tento build nepodporuje. Na Pi over:

```bash
uname -m
# ocakavane: aarch64
sudo snap install microk8s --classic
sudo usermod -a -G microk8s "$USER"
# Odhlas sa a znovu prihlas, aby sa nacitala skupina microk8s.
microk8s status --wait-ready
microk8s enable dns ingress cert-manager
microk8s kubectl get nodes -L kubernetes.io/arch
microk8s kubectl get ingressclass
```

Najprv nechaj GitHub Actions publikovat novy multiarch image (push do `main`
alebo manualne spustenie workflow na default branchi). Over platformy:

```bash
docker buildx imagetools inspect ghcr.io/jkralik/wedding:latest
# musi obsahovat linux/amd64 aj linux/arm64
```

Na Pi potom z tohto repozitara spusti deploy. Nastav triedu podla vystupu
`microk8s kubectl get ingressclass` (`public` je priklad; podla verzie a
konfiguracie to moze byt `nginx` alebo `traefik`):

```bash
microk8s kubectl config current-context
# Ak mas aj samostatny kubectl, over ze pouziva rovnaky MicroK8s cluster:
# kubectl config current-context
./deploy-local-k8s.sh --ingress-class public
microk8s kubectl -n wedding get pods -o wide
microk8s kubectl -n wedding get ingress,certificate
```

Docker na Pi nie je pri pouziti publikovaneho GHCR image potrebny.
GHCR package musi byt verejny; pri sukromnom package nastav `imagePullSecrets`
v deploymente. Bez `--context` script uprednostnuje lokalny `microk8s kubectl`
a pripne jeho aktualny kontext pre vsetky prikazy. Pre samostatny `kubectl`
je `--context` povinny, napriklad `./deploy-local-k8s.sh --context kind-test`.
Pri explicitnom kontexte sa uprednostni samostatny `kubectl`, ak existuje.
Globalny aktualny kontext sa nemeni.

Pre HTTPS musia DNS zaznamy oboch domen smerovat na verejnu IP pripojenia Pi
a router musi presmerovat TCP porty **80 a 443** na Pi. ACME HTTP-01 vyzaduje
verejne dostupny port 80. Nespravny `AAAA` zaznam moze overenie pokazit.
Bez verejneho pristupu mozes funkcnost webu overit lokalne, nezavisle od certifikatu:

```bash
microk8s kubectl -n wedding port-forward service/wedding-web 8080:80
# Na Pi otvor http://localhost:8080
```

## K8s deploy s HTTPS cez ACME

Predpoklady:

- v clustri je nainstalovany Ingress controller (`nginx`)
- v clustri je nainstalovany `cert-manager`
- administrator uz nastavil `ClusterIssuer letsencrypt-prod` pre tento cluster;
  wedding manifesty nespravuju ziadny issuer ani cert-manager
- DNS `A`/`AAAA` zaznamy pre `petra-jozef.eu` a `www.petra-jozef.eu` smeruju na ingress load balancer

Deploy:

```bash
kubectl apply -k k8s
```

Priama aplikacia cez `kubectl` obchadza kontroly deploy skriptu; pre bezny
deploy pouzi `./deploy-local-k8s.sh`. Obe cesty aplikuju iba namespace `wedding`
a jeho aplikacne zdroje, nie spolocny ClusterIssuer.

Kontrola certifikatu:

```bash
kubectl -n wedding get certificate
kubectl -n wedding describe certificate petra-jozef-eu-tls
kubectl -n wedding get ingress
```

Po uspesnom vydani certifikatu bude stranka dostupna na:

- https://petra-jozef.eu
- https://www.petra-jozef.eu
