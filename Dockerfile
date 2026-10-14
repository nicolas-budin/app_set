# --- Étape 1 : compilation ---
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /build
COPY pom.xml .
RUN mvn -q -B dependency:go-offline
COPY src ./src
RUN mvn -q -B package -DskipTests

# --- Étape 2 : image d'exécution ---
FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /build/target/app.jar app.jar
EXPOSE 8080
# Pas de USER fixe : OpenShift lance le conteneur avec un UID aléatoire
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
