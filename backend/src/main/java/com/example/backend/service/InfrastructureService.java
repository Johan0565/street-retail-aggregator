package com.example.backend.service;

import com.example.backend.dto.PoiDto;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;
import org.springframework.http.ResponseEntity;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

@Service
@Slf4j
public class InfrastructureService {

    private final RestTemplate restTemplate = new RestTemplate();

    public List<PoiDto> getInfrastructureNearby(double lat, double lon, int radius) {
        List<PoiDto> pois = new ArrayList<>();
        try {
            String overpassQuery = "[out:json];" +
                    "(" +
                    "node[\"station\"=\"subway\"](around:" + radius + "," + lat + "," + lon + ");" +
                    "node[\"amenity\"=\"cafe\"](around:" + radius + "," + lat + "," + lon + ");" +
                    "node[\"amenity\"=\"university\"](around:" + radius + "," + lat + "," + lon + ");" +
                    ");" +
                    "out body 15;";

            String url = "https://overpass-api.de/api/interpreter?data=" + overpassQuery;
            ResponseEntity<Map> response = restTemplate.getForEntity(url, Map.class);
            
            if (response.getBody() != null && response.getBody().containsKey("elements")) {
                List<Map<String, Object>> elements = (List<Map<String, Object>>) response.getBody().get("elements");
                for (Map<String, Object> element : elements) {
                    Map<String, String> tags = (Map<String, String>) element.get("tags");
                    if (tags != null) {
                        String name = tags.getOrDefault("name", "Объект");
                        String category = "unknown";
                        if (tags.containsKey("station") && tags.get("station").equals("subway")) category = "metro";
                        else if (tags.containsKey("amenity") && tags.get("amenity").equals("cafe")) category = "cafe";
                        else if (tags.containsKey("amenity") && tags.get("amenity").equals("university")) category = "university";
                        
                        double elementLat = (double) element.get("lat");
                        double elementLon = (double) element.get("lon");
                        double distance = calculateDistance(lat, lon, elementLat, elementLon);
                        
                        pois.add(PoiDto.builder()
                                .name(name)
                                .category(category)
                                .distanceMeters((int) distance)
                                .build());
                    }
                }
            }
        } catch (Exception e) {
            log.error("Error fetching POIs from Overpass API", e);
            pois.add(PoiDto.builder().name("Ближайшее метро (демо)").category("metro").distanceMeters(300).build());
        }
        
        pois.sort((p1, p2) -> Double.compare(p1.getDistanceMeters(), p2.getDistanceMeters()));
        return pois;
    }

    private double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
        final int R = 6371;
        double latDistance = Math.toRadians(lat2 - lat1);
        double lonDistance = Math.toRadians(lon2 - lon1);
        double a = Math.sin(latDistance / 2) * Math.sin(latDistance / 2)
                + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2))
                * Math.sin(lonDistance / 2) * Math.sin(lonDistance / 2);
        double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return R * c * 1000;
    }
}
