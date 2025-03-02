FROM openjdk:11-jre-slim

WORKDIR /app

# Add Maven/Gradle dependencies layer
COPY target/*.jar app.jar

EXPOSE 8080

# Add wait-for-it script to wait for MySQL to be ready
ADD https://raw.githubusercontent.com/vishnubob/wait-for-it/master/wait-for-it.sh /wait-for-it.sh
RUN chmod +x /wait-for-it.sh

# Use wait-for-it to ensure MySQL is up before starting the app
ENTRYPOINT ["/bin/sh", "-c", "/wait-for-it.sh mysql:3306 -- java -jar app.jar"]