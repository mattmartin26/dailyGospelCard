/**
 * @description Service to fetch the Gospel of the day from an external API via Named Credential.
 * Uses a placeholder Named Credential 'USCCB_Daily_Readings'. Replace endpoint and parsing with real API details.
 * - with sharing: respect org sharing
 * - User-mode DML not needed (no DML). No @future; use Queueable if later needed.
 * - Exposes an invocable method for Flow usage (returns title, reference, and body text).
 */
public with sharing class DailyGospelService {
    public class GospelResponse {
        @AuraEnabled public String title;
        @AuraEnabled public String reference;
        @AuraEnabled public String body;
        public GospelResponse() {}
        public GospelResponse(String t, String r, String b) {
            title = t; reference = r; body = b;
        }
    }

    /**
     * @description Core callout to external API. Currently built for placeholder JSON shape.
     * Expected mock JSON (adjust to real API):
     * {
     *   "date": "2026-03-23",
     *   "readings": [
     *     {"type": "gospel", "title": "Holy Gospel according to John", "reference": "Jn 3:16-21", "text": "In those days..."}
     *   ]
     * }
     */
    @AuraEnabled(cacheable=true)
    public static GospelResponse getTodayGospel() {
        // Return early default
        Date today = Date.today();
        HttpResponse res;
        try {
            HttpRequest req = new HttpRequest();
            req.setMethod('GET');
            // Replace with actual named credential URL path once known. Path example: /daily?date=YYYY-MM-DD
            String path = '/daily?date=' + String.valueOf(today);
            req.setEndpoint('callout:USCCB_Daily_Readings' + path);
            // If API key is needed later, set header here, e.g. req.setHeader('x-api-key','{!$Credential.Password}');
            Http http = new Http();
            res = http.send(req);
        } catch (System.CalloutException ex) {
            // Sanitize message
            String safeMsg = ex.getMessage();
            throw new AuraHandledException('Failed to contact readings service: ' + safeMsg);
        }

        if (res == null) {
            throw new AuraHandledException('No response from readings service');
        }
        Integer status = res.getStatusCode();
        if (status < 200 || status >= 300) {
            throw new AuraHandledException('Readings service error: HTTP ' + status);
        }

        String body = res.getBody();
        if (String.isBlank(body)) {
            throw new AuraHandledException('Readings service returned empty payload');
        }

        try {
            // Parse placeholder shape
            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(body);
            List<Object> readings = (List<Object>) root.get('readings');
            if (readings == null || readings.isEmpty()) {
                throw new AuraHandledException('No readings found for today');
            }
            for (Object o : readings) {
                Map<String,Object> r = (Map<String,Object>) o;
                String type = (String) r.get('type');
                if (type != null && type.toLowerCase() == 'gospel') {
                    String title = (String) r.get('title');
                    String reference = (String) r.get('reference');
                    String text = (String) r.get('text');
                    return new GospelResponse(
                        String.isBlank(title) ? 'Gospel' : title,
                        reference,
                        text
                    );
                }
            }
            // If not found explicitly, return first reading as fallback
            Map<String,Object> first = (Map<String,Object>) readings[0];
            return new GospelResponse(
                (String) first.get('title'),
                (String) first.get('reference'),
                (String) first.get('text')
            );
        } catch (Exception e) {
            throw new AuraHandledException('Failed to parse readings: ' + e.getMessage());
        }
    }

    /**
     * @description Invocable method for Flow. Returns a single-element list with GospelResponse fields mapped to outputs.
     */
    public class FlowInput {
        @InvocableVariable(required=false)
        public Date date; // optional future enhancement (today-only per requirements)
    }
    public class FlowOutput {
        @InvocableVariable public String title;
        @InvocableVariable public String reference;
        @InvocableVariable public String body;
    }

    @InvocableMethod(label='Get Gospel of the Day' description='Fetches the Gospel reading for today from the external readings service')
    public static List<FlowOutput> getGospelForFlow(List<FlowInput> inputs) {
        GospelResponse gr = getTodayGospel();
        FlowOutput out = new FlowOutput();
        out.title = gr != null ? gr.title : null;
        out.reference = gr != null ? gr.reference : null;
        out.body = gr != null ? gr.body : null;
        return new List<FlowOutput>{ out };
    }
}