package com.example.backend.service;

import com.example.backend.dto.PoiDto;
import com.example.backend.repository.SearchProfileRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;
import org.springframework.http.ResponseEntity;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;

@Service
@Slf4j
@RequiredArgsConstructor
public class InfrastructureService {

    private final SearchProfileRepository searchProfileRepository;
    private final RestTemplate restTemplate = new RestTemplate();

    public List<PoiDto> getInfrastructureNearby(double lat, double lon, int radius, Long profileId) {
        String osmTag = null;
        if (profileId != null) {
            osmTag = searchProfileRepository.findById(profileId)
                    .map(p -> p.getBusinessCategory() != null ? p.getBusinessCategory().getOsmTag() : null)
                    .orElse(null);
        }
        return getPoisFromOverpass(lat, lon, radius, osmTag);
    }

    public int countCompetitors(double lat, double lon, int radius, String osmTag) {
        if (osmTag == null || osmTag.isEmpty()) return 0;
        try {
            String query = "[out:json];node[" + osmTag + "](around:" + radius + "," + lat + "," + lon + ");out count;";
            String url = "https://overpass-api.de/api/interpreter?data=" + query;
            
            ResponseEntity<Map> response = restTemplate.getForEntity(url, Map.class);
            if (response.getBody() != null && response.getBody().containsKey("elements")) {
                List<Map<String, Object>> elements = (List<Map<String, Object>>) response.getBody().get("elements");
                if (!elements.isEmpty()) {
                    Map<String, Object> tags = (Map<String, Object>) elements.get(0).get("tags");
                    if (tags != null && tags.containsKey("total")) {
                        return Integer.parseInt(tags.get("total").toString());
                    }
                }
            }
        } catch (Exception e) {
            log.error("Error counting competitors from Overpass", e);
        }
        return 0;
    }

    private List<PoiDto> getPoisFromOverpass(double lat, double lon, int radius, String competitorTag) {
        List<PoiDto> pois = new ArrayList<>();
        try {
            StringBuilder overpassQuery = new StringBuilder("[out:json];(");
            overpassQuery.append("node[\"station\"=\"subway\"](around:").append(radius).append(",").append(lat).append(",").append(lon).append(");");
            overpassQuery.append("node[\"amenity\"=\"cafe\"](around:").append(radius).append(",").append(lat).append(",").append(lon).append(");");
            overpassQuery.append("node[\"amenity\"=\"university\"](around:").append(radius).append(",").append(lat).append(",").append(lon).append(");");
            
            if (competitorTag != null && !competitorTag.isEmpty()) {
                overpassQuery.append("node[").append(competitorTag).append("](around:").append(radius).append(",").append(lat).append(",").append(lon).append(");");
            }
            
            overpassQuery.append(");out body 25;"); // Increased limit to see more POIs

            String url = "https://overpass-api.de/api/interpreter?data=" + overpassQuery.toString();
            ResponseEntity<Map> response = restTemplate.getForEntity(url, Map.class);
            
            if (response.getBody() != null && response.getBody().containsKey("elements")) {
                List<Map<String, Object>> elements = (List<Map<String, Object>>) response.getBody().get("elements");
                for (Map<String, Object> element : elements) {
                    Map<String, String> tags = (Map<String, String>) element.get("tags");
                    if (tags != null) {
                        String name = tags.getOrDefault("name", "Объект");
                        String category = "unknown";
                        boolean isCompetitor = false;

                        // Identify category and if it's a competitor
                        if (tags.containsKey("station") && tags.get("station").equals("subway")) category = "metro";
                        else if (tags.containsKey("amenity") && tags.get("amenity").equals("cafe")) category = "cafe";
                        else if (tags.containsKey("amenity") && tags.get("amenity").equals("university")) category = "university";

                        if (competitorTag != null && !competitorTag.isEmpty()) {
                            String[] tagParts = competitorTag.split("=");
                            if (tagParts.length == 2) {
                                if (tagParts[1].equals(tags.get(tagParts[0]))) {
                                    isCompetitor = true;
                                    category = "competitor"; // High-level category for frontend if needed
                                }
                            }
                        }
                        
                        double eLat = (double) element.get("lat");
                        double eLon = (double) element.get("lon");
                        double distance = calculateDistance(lat, lon, eLat, eLon);
                        
                        pois.add(PoiDto.builder()
                                .name(name)
                                .category(category)
                                .distanceMeters((int) distance)
                                .isCompetitor(isCompetitor)
                                .build());
                    }
                }
            }
        } catch (Exception e) {
            log.error("Error fetching POIs from Overpass", e);
        }
        // De-duplicate if competitor tag matches one of the standard tags (e.g. cafe)
        // For simplicity, we keep them for now as they'll have isCompetitor=true
        
        pois.sort(Comparator.comparingDouble(PoiDto::getDistanceMeters));
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
