package com.melo;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

import java.io.File;
import java.nio.file.Files;
import java.util.List;

@SpringBootApplication
public class SpringBackendApplication {

	public static void main(String[] args) {
		loadDotenv();
		SpringApplication.run(SpringBackendApplication.class, args);
	}

	private static void loadDotenv() {
		String[] paths = {".env", "../.env", "SpringBackend/.env"};
		for (String path : paths) {
			File file = new File(path);
			if (file.exists() && file.isFile()) {
				try {
					List<String> lines = Files.readAllLines(file.toPath());
					for (String line : lines) {
						line = line.trim();
						if (line.isEmpty() || line.startsWith("#") || !line.contains("=")) {
							continue;
						}
						int eqIdx = line.indexOf('=');
						String key = line.substring(0, eqIdx).trim();
						String value = line.substring(eqIdx + 1).trim();
						if (value.startsWith("\"") && value.endsWith("\"") && value.length() >= 2) {
							value = value.substring(1, value.length() - 1);
						} else if (value.startsWith("'") && value.endsWith("'") && value.length() >= 2) {
							value = value.substring(1, value.length() - 1);
						}
						if (System.getProperty(key) == null && System.getenv(key) == null) {
							System.setProperty(key, value);
						}
					}
					System.out.println("[Security] Loaded environment configuration from " + file.getAbsolutePath());
					break;
				} catch (Exception e) {
					System.err.println("[Security] Could not read .env from " + path + ": " + e.getMessage());
				}
			}
		}
	}
}
