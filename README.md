# hello-world

Application Spring Boot minimale qui répond `Hello World` sur `GET /`, déployée sur OpenShift.

- Java 21, Spring Boot 3.5
- Endpoints de santé : `/actuator/health/liveness` et `/actuator/health/readiness`
- Image construite par OpenShift à partir du `Dockerfile` (Java et Maven ne sont pas nécessaires en local)

## Structure

```text
.
├── pom.xml
├── Dockerfile                      # build multi-stage (Maven -> JRE 21)
├── src/main/java/com/example/hello/
│   ├── HelloApplication.java
│   └── HelloController.java        # GET / -> "Hello World"
├── src/main/resources/application.properties
├── k8s/
│   ├── deployment.yaml             # Deployment : image, probes, ressources, trigger d'image
│   ├── service.yaml                # Service sur le port 8080
│   └── route.yaml                  # Route HTTPS (edge)
└── docs/deploiement-openshift.md   # toutes les commandes
```

## Démarrage rapide

Prérequis : la CLI `oc` installée et une session ouverte sur le cluster (`oc login`).

```bash
oc new-project hello
oc new-build --binary --strategy=docker --name=hello-world
oc start-build hello-world --from-dir=. --follow
oc apply -f k8s/

curl https://$(oc get route hello-world -o jsonpath='{.spec.host}')
# Hello World
```

## Documentation

La procédure complète se trouve dans [docs/deploiement-openshift.md](docs/deploiement-openshift.md). Elle couvre le test en local, le build, le déploiement, les health checks, les mises à jour, l'exploitation, le dépannage et le nettoyage.
