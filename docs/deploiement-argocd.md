# Déployer hello-world en DEV, INT et PRD avec un ApplicationSet ArgoCD

Ce guide déploie l'application `hello-world` dans 3 environnements sur OpenShift, avec **OpenShift GitOps** (ArgoCD). Toutes les commandes nécessaires y sont.

Pour le déploiement manuel dans un seul projet, sans ArgoCD, voir [deploiement-openshift.md](deploiement-openshift.md).

Pour la liste complète des commandes avec l'explication de chacune, voir la **section 15**, en fin de document.

## 1. Principe

```text
            hello-build (namespace)
  oc start-build -> ImageStream hello-world:latest
  oc tag         -> hello-world:1.0.0, 1.0.1...       (versions figées)
                         │  droit image-puller
        ┌────────────────┼────────────────┐
   hello-dev         hello-int        hello-prd       (1 namespace par environnement)
        ▲                ▲                ▲
   Application      Application      Application     (générées par l'ApplicationSet)
        └──── openshift-gitops / ApplicationSet hello-world ────┘
                 lit envs/* et charts/hello-world dans Git
```

- L'image est **construite une seule fois**, dans `hello-build`, puis **taguée avec un numéro de version**.
- **Git décrit ce qui tourne** : chaque environnement indique dans `envs/<env>/values.yaml` la version (`image.tag`) qu'il doit faire tourner.
- L'**ApplicationSet** crée une Application ArgoCD par dossier `envs/*`. Chaque Application déploie le chart Helm dans son namespace, puis le garde aligné sur Git.

| Dossier / fichier | Rôle |
| --- | --- |
| `charts/hello-world/` | Chart Helm : Deployment, Service et Route communs aux 3 environnements |
| `charts/hello-world/values.yaml` | Valeurs par défaut |
| `envs/dev/values.yaml`, `envs/int/values.yaml`, `envs/prd/values.yaml` | Ce qui change par environnement : `env`, `replicas`, `image.tag` |
| `argocd/applicationset.yaml` | L'ApplicationSet, qui génère `hello-world-dev`, `hello-world-int` et `hello-world-prd` |

| Environnement | Application ArgoCD | Namespace | Replicas |
| --- | --- | --- | --- |
| DEV | `hello-world-dev` | `hello-dev` | 1 |
| INT | `hello-world-int` | `hello-int` | 1 |
| PRD | `hello-world-prd` | `hello-prd` | 2 |

## 2. Prérequis

- L'opérateur **OpenShift GitOps** est installé sur le cluster. Il crée l'instance ArgoCD dans le namespace `openshift-gitops`. Pour vérifier :

  ```bash
  oc get pods -n openshift-gitops
  ```

- Les CLI `oc` et `git` sont installées. `helm` est optionnel (`brew install helm`).
- Un compte **cluster-admin** est nécessaire pour la mise en place : création des namespaces et de l'ApplicationSet.

```bash
oc login --token=<TOKEN> --server=https://api.<cluster>:6443
oc whoami
```

## 3. Pousser le code sur GitHub

ArgoCD lit le chart et les values dans Git. Il faut donc d'abord publier le projet.

Le dépôt est **public** : `https://github.com/nicolas-budin/app_set.git`, branche `main`. L'URL est déjà renseignée dans `argocd/applicationset.yaml`, aux 2 champs `repoURL`.

Avant de créer l'ApplicationSet, les dossiers `charts/`, `envs/` et `argocd/` doivent être sur `main` :

```bash
git add .
git commit -m "ApplicationSet ArgoCD : chart Helm et environnements DEV, INT, PRD"
git push
```

Pour utiliser un autre dépôt, remplacer l'URL dans `argocd/applicationset.yaml`. Sur macOS :

```bash
sed -i '' 's#https://github.com/nicolas-budin/app_set.git#<nouvelle-url>#g' argocd/applicationset.yaml
```

Si le dépôt est privé, il faut aussi le déclarer dans ArgoCD avec ses identifiants : console ArgoCD > *Settings* > *Repositories*.

## 4. Construire et versionner l'image

```bash
oc new-project hello-build
oc new-build --binary --strategy=docker --name=hello-world -n hello-build
oc start-build hello-world --from-dir=. --follow -n hello-build

# Figer cette image sous un numéro de version
oc tag hello-build/hello-world:latest hello-build/hello-world:1.0.0

oc get is hello-world -n hello-build      # les tags latest et 1.0.0 doivent apparaître
```

## 5. Préparer les 3 namespaces

Pour chaque environnement :

- créer le namespace ;
- ajouter le label `argocd.argoproj.io/managed-by=openshift-gitops`. Avec ce label, l'opérateur donne à ArgoCD les droits de déployer dans ce namespace ;
- autoriser le namespace à télécharger les images de `hello-build`.

```bash
for env in dev int prd; do
  oc new-project hello-$env
  oc label namespace hello-$env argocd.argoproj.io/managed-by=openshift-gitops
  oc policy add-role-to-group system:image-puller \
    system:serviceaccounts:hello-$env -n hello-build
done

oc get namespaces -l argocd.argoproj.io/managed-by=openshift-gitops
```

## 6. Vérifier le chart en local (optionnel)

```bash
helm lint charts/hello-world -f envs/dev/values.yaml
helm template hello-world charts/hello-world -f envs/dev/values.yaml
helm template hello-world charts/hello-world -f envs/prd/values.yaml | grep -E 'replicas|image:|value:'
```

## 7. Créer l'ApplicationSet

```bash
oc apply -n openshift-gitops -f argocd/applicationset.yaml

oc get applicationset -n openshift-gitops
oc get applications -n openshift-gitops
```

Au bout de quelques secondes, 3 Applications apparaissent : `hello-world-dev`, `hello-world-int` et `hello-world-prd`. Elles doivent passer à `Synced` et `Healthy`.

```bash
oc get applications -n openshift-gitops \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status
```

## 8. Console ArgoCD

```bash
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}'
```

Ouvrir `https://<host>` et se connecter avec **Log in via OpenShift**. La console montre les 3 Applications, leurs ressources et l'historique des synchronisations.

## 9. Vérifier les 3 environnements

```bash
for env in dev int prd; do
  HOST=$(oc get route hello-world -n hello-$env -o jsonpath='{.spec.host}')
  echo "$env -> $(curl -s https://$HOST)"
done
# dev -> Hello World !!! (DEV)
# int -> Hello World !!! (INT)
# prd -> Hello World !!! (PRD)
```

Si le certificat du cluster est auto-signé, ajouter `-k` à `curl`.

## 10. Livrer une nouvelle version et la promouvoir

**1. Construire et taguer la nouvelle version :**

```bash
oc start-build hello-world --from-dir=. --follow -n hello-build
oc tag hello-build/hello-world:latest hello-build/hello-world:1.0.1
```

**2. Déployer en DEV.** Dans `envs/dev/values.yaml`, passer `tag: "1.0.1"`, puis :

```bash
git commit -am "DEV : hello-world 1.0.1"
git push
```

ArgoCD vérifie le dépôt toutes les 3 minutes environ. Pour forcer la mise à jour, cliquer sur **Refresh** dans la console, ou lancer :

```bash
oc annotate application hello-world-dev -n openshift-gitops \
  argocd.argoproj.io/refresh=normal --overwrite
oc rollout status deploy/hello-world -n hello-dev
```

**3. Promouvoir en INT, puis en PRD**, une fois la version validée : faire la même modification dans `envs/int/values.yaml`, puis dans `envs/prd/values.yaml`, avec un commit et un push à chaque fois.

**Revenir en arrière :** annuler le commit concerné. ArgoCD redéploie alors la version précédente.

```bash
git log --oneline -- envs/prd/values.yaml
git revert <commit>
git push
```

Toutes les modifications de configuration passent par Git : nombre de replicas, ressources, nouvelle variable d'environnement. Une modification de `charts/hello-world/` s'applique aux 3 environnements. Une modification de `envs/<env>/values.yaml` ne touche que cet environnement.

## 11. Ajouter un environnement

Exemple : un environnement `rec`.

```bash
mkdir envs/rec
cp envs/int/values.yaml envs/rec/values.yaml     # puis passer env: REC

oc new-project hello-rec
oc label namespace hello-rec argocd.argoproj.io/managed-by=openshift-gitops
oc policy add-role-to-group system:image-puller system:serviceaccounts:hello-rec -n hello-build

git add envs/rec && git commit -m "Ajout de l'environnement REC" && git push
```

L'ApplicationSet détecte le nouveau dossier et crée l'Application `hello-world-rec` toute seule.

## 12. Exploiter

```bash
oc get applications -n openshift-gitops                        # état des 3 environnements
oc describe application hello-world-dev -n openshift-gitops    # détails, erreurs, dernière synchro
oc get all -n hello-dev                                        # ressources de DEV
oc logs -f deploy/hello-world -n hello-dev                     # logs de l'appli en DEV
oc get is hello-world -n hello-build                           # versions d'image disponibles
```

**`selfHeal` est activé.** Une modification faite à la main dans le cluster (`oc scale`, `oc set env`, `oc edit`…) est annulée par ArgoCD en quelques secondes. Pour changer quelque chose de façon durable, il faut passer par Git.

## 13. Dépanner

```bash
oc describe applicationset hello-world -n openshift-gitops     # erreurs de génération
oc describe application hello-world-dev -n openshift-gitops    # erreurs de synchro
oc get events -n hello-dev --sort-by=.lastTimestamp
oc logs -n openshift-gitops deploy/openshift-gitops-applicationset-controller
```

| Symptôme | Cause probable | Que faire |
| --- | --- | --- |
| Aucune Application n'est créée | Mauvaise URL de dépôt, dépôt privé, ou dossiers `envs/*` absents de la branche `main` | `oc describe applicationset hello-world -n openshift-gitops`, puis vérifier l'URL et le push |
| Application en `Unknown` / `ComparisonError` | Chart ou fichier de values introuvable, ou erreur dans un template Helm | Tester `helm template` en local (section 6) |
| `... is forbidden: User "system:serviceaccount:openshift-gitops:..."` | Label `managed-by` absent du namespace | `oc label namespace hello-<env> argocd.argoproj.io/managed-by=openshift-gitops` |
| `ImagePullBackOff` | Tag de version absent ou droit `image-puller` manquant | `oc get is hello-world -n hello-build` pour voir les tags, puis relancer la commande `oc policy add-role-to-group` de la section 5 |
| Application `OutOfSync` en permanence | Modification faite à la main, ou champ ajouté par le cluster | Comparer avec le bouton **App Diff** dans la console |
| La nouvelle version n'est pas déployée | Push pas fait, ou ArgoCD pas encore rafraîchi | `git log origin/main`, puis faire un **Refresh** (section 10) |

## 14. Nettoyer

Supprimer l'ApplicationSet supprime aussi les 3 Applications. Grâce au finalizer `resources-finalizer.argocd.argoproj.io`, leurs ressources (Deployment, Service, Route) sont supprimées aussi.

```bash
oc delete applicationset hello-world -n openshift-gitops
oc delete project hello-dev hello-int hello-prd hello-build
```

## 15. Récapitulatif : toutes les commandes expliquées

Les commandes de la mise en place sont listées ici dans l'ordre, chacune avec son explication. Lance-les depuis la racine du projet. Les étapes 0 à 4 ne se font qu'une seule fois. Ensuite, tout passe par Git.

### Étape 0 : installer `oc` et se connecter

```bash
brew install openshift-cli
oc login --token=<TOKEN> --server=https://api.<cluster>:6443
oc get pods -n openshift-gitops
```

| Commande | Ce qu'elle fait |
| --- | --- |
| `brew install openshift-cli` | Installe la CLI `oc` sur macOS. C'est l'outil en ligne de commande d'OpenShift : `kubectl` + des commandes propres à OpenShift (build, route, projet…). |
| `oc login --token=<TOKEN> --server=https://api.<cluster>:6443` | Te connecte au cluster. `--server` est l'adresse de l'API du cluster. `--token` est ton jeton d'accès personnel, copié depuis la console web (menu utilisateur > *Copy login command*). Toutes les commandes `oc` suivantes s'exécutent avec ton identité. |
| `oc get pods -n openshift-gitops` | Liste les pods du namespace `openshift-gitops` (`-n` = namespace). Si les pods `openshift-gitops-server`, `...-application-controller` et `...-applicationset-controller` sont `Running`, ArgoCD est bien installé. |

### Étape 1 : pousser le code sur GitHub

```bash
git add .
git commit -m "ApplicationSet ArgoCD : DEV, INT, PRD"
git push
```

| Commande | Ce qu'elle fait |
| --- | --- |
| `git add .` | Ajoute à la prochaine sauvegarde tous les fichiers modifiés ou nouveaux du dossier courant : `charts/`, `envs/`, `argocd/`, docs… |
| `git commit -m "..."` | Enregistre ces modifications dans l'historique local, avec un message. |
| `git push` | Envoie les commits vers GitHub (`origin/main`). **C'est indispensable** : ArgoCD ne voit que ce qui est sur GitHub, pas ce qui est sur ton disque. |

### Étape 2 : construire l'image et lui donner une version

```bash
oc new-project hello-build
oc new-build --binary --strategy=docker --name=hello-world -n hello-build
oc start-build hello-world --from-dir=. --follow -n hello-build
oc tag hello-build/hello-world:latest hello-build/hello-world:1.0.0
```

| Commande | Ce qu'elle fait |
| --- | --- |
| `oc new-project hello-build` | Crée le projet (namespace) `hello-build` et en fait ton projet courant. C'est là que l'image est construite et stockée, à part des environnements. |
| `oc new-build --binary --strategy=docker --name=hello-world -n hello-build` | Crée deux objets, **sans rien construire encore** :<br>• un **BuildConfig** `hello-world`, la « recette » du build. `--strategy=docker` : exécuter le `Dockerfile`. `--binary` : les sources seront envoyées depuis ton poste, pas récupérées dans Git.<br>• un **ImageStream** `hello-world`, l'emplacement où l'image produite sera rangée dans le registre interne d'OpenShift. |
| `oc start-build hello-world --from-dir=. --follow -n hello-build` | **Lance le build.** `--from-dir=.` envoie le dossier courant (Dockerfile, pom.xml, src/) au cluster. OpenShift exécute le Dockerfile (compilation Maven puis image Java 21) et pousse le résultat dans `hello-world:latest`. `--follow` affiche les logs du build en direct. |
| `oc tag hello-build/hello-world:latest hello-build/hello-world:1.0.0` | Ajoute un **second nom**, `1.0.0`, à l'image actuelle de `latest`. C'est comme un tag Git : `latest` bougera au prochain build, mais `1.0.0` désignera toujours cette image précise. Les fichiers `envs/*/values.yaml` font référence à ce numéro. |

### Étape 3 : préparer les 3 namespaces

```bash
for env in dev int prd; do
  oc new-project hello-$env
  oc label namespace hello-$env argocd.argoproj.io/managed-by=openshift-gitops
  oc policy add-role-to-group system:image-puller system:serviceaccounts:hello-$env -n hello-build
done
```

La boucle `for env in dev int prd; do ... done` exécute les 3 commandes trois fois, avec `$env` = `dev`, puis `int`, puis `prd`.

| Commande | Ce qu'elle fait |
| --- | --- |
| `oc new-project hello-$env` | Crée le namespace de l'environnement : `hello-dev`, `hello-int`, `hello-prd`. |
| `oc label namespace hello-$env argocd.argoproj.io/managed-by=openshift-gitops` | Ajoute un label au namespace. L'opérateur OpenShift GitOps surveille ce label : quand il le voit, il **donne à ArgoCD les droits de déployer** dans ce namespace. Sans ce label, la synchro échoue avec une erreur `forbidden`. |
| `oc policy add-role-to-group system:image-puller system:serviceaccounts:hello-$env -n hello-build` | Donne le rôle `image-puller` (droit de télécharger des images) à **tous les comptes de service** du namespace `hello-$env`, sur le namespace `hello-build` (`-n`). Sans ça, les pods de DEV/INT/PRD n'ont pas le droit de lire l'image stockée dans `hello-build` : erreur `ImagePullBackOff`. |

### Étape 4 : créer l'ApplicationSet

```bash
oc apply -n openshift-gitops -f argocd/applicationset.yaml
```

| Commande | Ce qu'elle fait |
| --- | --- |
| `oc apply -n openshift-gitops -f argocd/applicationset.yaml` | Envoie le fichier `applicationset.yaml` au cluster, dans le namespace d'ArgoCD. `apply` crée l'objet s'il n'existe pas, ou le met à jour sinon. **C'est la seule commande qui « branche » ArgoCD sur le dépôt.** Ensuite, ArgoCD lit `envs/*` sur GitHub, crée les 3 Applications, et chacune déploie le chart dans son namespace. |

### Étape 5 : vérifier

```bash
oc get applications -n openshift-gitops

for env in dev int prd; do
  curl -s https://$(oc get route hello-world -n hello-$env -o jsonpath='{.spec.host}'); echo
done
```

| Commande | Ce qu'elle fait |
| --- | --- |
| `oc get applications -n openshift-gitops` | Liste les Applications ArgoCD. Tu dois voir `hello-world-dev`, `hello-world-int` et `hello-world-prd`, avec :<br>• **SYNC** = `Synced` : le cluster correspond à Git ;<br>• **HEALTH** = `Healthy` : les pods tournent et sont prêts. |
| `oc get route hello-world -n hello-$env -o jsonpath='{.spec.host}'` | Récupère l'adresse publique de la Route dans un namespace. `-o jsonpath` extrait seulement le champ `spec.host`, par exemple `hello-world-hello-dev.apps.mon-cluster.com`. |
| `curl -s https://<host>` | Appelle l'appli à cette adresse et affiche sa réponse. `-s` masque la barre de progression, `-k` (à ajouter si besoin) ignore un certificat auto-signé. Chaque environnement doit répondre avec son nom : `Hello World !!! (DEV)`… |

### Livrer une nouvelle version

```bash
oc start-build hello-world --from-dir=. --follow -n hello-build
oc tag hello-build/hello-world:latest hello-build/hello-world:1.0.1
# mettre tag: "1.0.1" dans envs/dev/values.yaml, puis :
git commit -am "DEV : 1.0.1" && git push
# une fois DEV validé, même chose dans envs/int puis envs/prd
```

| Commande | Ce qu'elle fait |
| --- | --- |
| `oc start-build hello-world --from-dir=. --follow -n hello-build` | Reconstruit l'image avec le nouveau code. `latest` pointe maintenant sur la nouvelle image. **Aucun environnement ne change**, car ils utilisent `1.0.0`. |
| `oc tag hello-build/hello-world:latest hello-build/hello-world:1.0.1` | Donne le numéro `1.0.1` à cette nouvelle image. |
| Modifier `tag: "1.0.1"` dans `envs/dev/values.yaml` | Indique dans Git que DEV doit faire tourner la 1.0.1. |
| `git commit -am "DEV : 1.0.1" && git push` | `-a` prend tous les fichiers déjà suivis qui ont été modifiés, `-m` ajoute le message. Le push envoie le changement sur GitHub. Dans les 3 minutes environ, ArgoCD le détecte et met à jour le Deployment de `hello-dev` : rolling update vers la 1.0.1. INT et PRD ne bougent pas. |
| Même chose dans `envs/int/values.yaml`, puis `envs/prd/values.yaml` | Promotion : la même image 1.0.1, déjà testée en DEV, passe en INT puis en PRD. |
