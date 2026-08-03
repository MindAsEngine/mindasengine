FROM maven:3.9.9-eclipse-temurin-17 AS build

# Сначала pom.xml - слой с зависимостями кэшируется и не пересобирается при правках кода.
COPY pom.xml /home/app/pom.xml
RUN mvn -f /home/app/pom.xml -B dependency:go-offline

COPY src /home/app/src
RUN mvn -f /home/app/pom.xml -B clean package -DskipTests

# JRE вместо JDK: образ меньше. Тег зафиксирован, latest ломается при смене мажора Java.
FROM eclipse-temurin:17-jre

WORKDIR /usr/local/lib
COPY --from=build /home/app/target/mindasengine-alfa.jar /usr/local/lib/mindasengine.jar

EXPOSE 1337

ENTRYPOINT ["java","-jar","/usr/local/lib/mindasengine.jar"]
