# hello-world

Application Spring Boot minimale déployée sur OpenShift dans 3 environnements (DEV, INT, PRD) par un **ApplicationSet ArgoCD**. Sur `GET /`, elle répond `Hello World !!! (<ENV>) - Message secret : <message>`. Le message vient d'un Secret Kubernetes propre à chaque environnement.

- Java 21, Spring Boot 3.5
- L'environnement affiché vient de la variable `APP_ENV` (`local` par défaut)
- Le message vient de la variable `SECRET_MESSAGE`, alimentée par le Secret `hello-world-secret`
- Endpoints de santé : `/actuator/health/liveness` et `/actuator/health/readiness`
- Image construite par OpenShift à partir du `Dockerfile` (Java et Maven ne sont pas nécessaires en local)

## Structure

```text
.
├── pom.xml
├── Dockerfile                        # build multi-stage (Maven -> JRE 21)
├── src/main/java/com/example/hello/
│   ├── HelloApplication.java
│   └── HelloController.java          # GET / -> "Hello World !!! (<APP_ENV>) - Message secret : <SECRET_MESSAGE>"
├── src/main/resources/application.properties
├── charts/hello-world/               # chart Helm : Deployment, Service, Route, Secret
├── envs/
│   ├── dev/values.yaml               # DEV -> namespace hello-dev (version, replicas, message secret)
│   ├── int/values.yaml               # INT -> namespace hello-int
│   └── prd/values.yaml               # PRD -> namespace hello-prd (2 replicas)
├── argocd/applicationset.yaml        # 1 dossier envs/* = 1 Application ArgoCD
├── k8s/                              # manifestes du déploiement manuel (un seul projet, sans ArgoCD)
└── docs/
    ├── deploiement-argocd.md         # DEV/INT/PRD avec ArgoCD : toutes les commandes
    └── deploiement-openshift.md      # déploiement manuel avec oc : toutes les commandes
```

## Démarrage rapide (ArgoCD)

Prérequis :

- opérateur OpenShift GitOps installé ;
- `oc login` avec un compte cluster-admin ;
- les dossiers `charts/`, `envs/` et `argocd/` poussés sur la branche `main` de https://github.com/nicolas-budin/app_set (dépôt lu par ArgoCD).

```bash
# Image construite une fois, puis versionnée
oc new-project hello-build
oc new-build --binary --strategy=docker --name=hello-world -n hello-build
oc start-build hello-world --from-dir=. --follow -n hello-build
oc tag hello-build/hello-world:latest hello-build/hello-world:1.0.0

# Namespaces des 3 environnements
for env in dev int prd; do
  oc new-project hello-$env
  oc label namespace hello-$env argocd.argoproj.io/managed-by=openshift-gitops
  oc policy add-role-to-group system:image-puller system:serviceaccounts:hello-$env -n hello-build
done

# ApplicationSet -> Applications hello-world-dev, hello-world-int, hello-world-prd
oc apply -n openshift-gitops -f argocd/applicationset.yaml
oc get applications -n openshift-gitops
```

Pour promouvoir une version, modifie `image.tag` dans `envs/<env>/values.yaml`, puis fais un commit et un push.

> ⚠️ **Dépôt public** : les messages secrets (`secretMessage` dans `envs/*/values.yaml`, `k8s/secret.yaml`) sont lisibles par tous sur GitHub. Ils servent à la démo : n'y mets jamais de vrai mot de passe. Les alternatives sont dans la section « Message secret » de la doc ArgoCD.

## Documentation

- [docs/deploiement-argocd.md](docs/deploiement-argocd.md) : le principe, la mise en place, la promotion DEV → INT → PRD, l'ajout d'un environnement, l'exploitation, le dépannage et le nettoyage.
- [docs/deploiement-openshift.md](docs/deploiement-openshift.md) : le déploiement manuel dans un seul projet avec `oc` (`oc new-app` ou `oc apply -f k8s/`), utile pour apprendre et tester.
