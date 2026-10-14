package com.example.hello;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HelloController {

    // Environnement courant (DEV, INT, PRD), injecté par le Deployment via la variable APP_ENV
    @Value("${APP_ENV:local}")
    private String env;

    @GetMapping("/")
    public String hello() {
        return "Hello World !!! (" + env + ")";
    }
}
