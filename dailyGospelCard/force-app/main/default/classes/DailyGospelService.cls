public with sharing class DailyGospelService {
    public class GospelResponse {
        @AuraEnabled public String title;
        @AuraEnabled public String reference;
        @AuraEnabled public String body;

        public GospelResponse() {}

        public GospelResponse(String t, String r, String b) {
            title = t;
            reference = r;
            body = b;
        }
    }

    @AuraEnabled(cacheable=true)
    public static GospelResponse getTodayGospel() {
        return getGospelForDate(Date.today());
    }

    private static GospelResponse getGospelForDate(Date targetDate) {
        HttpResponse res;

        try {
            HttpRequest req = new HttpRequest();
            req.setMethod('GET');
            req.setTimeout(20000);

            // USCCB dated page pattern: /bible/readings/MMDDYY.cfm
            String mm = String.valueOf(targetDate.month()).leftPad(2, '0');
            String dd = String.valueOf(targetDate.day()).leftPad(2, '0');
            String yy = String.valueOf(Math.mod(targetDate.year(), 100)).leftPad(2, '0');
            String path = '/bible/readings/' + mm + dd + yy + '.cfm';
            // Direct endpoint used instead of a Named Credential.
            // This requires a Remote Site Setting for https://bible.usccb.org in the target org.
            req.setEndpoint('https://bible.usccb.org' + path);

            Http http = new Http();
            res = http.send(req);
        } catch (System.CalloutException ex) {
            throw new AuraHandledException('Failed to contact USCCB: ' + ex.getMessage());
        }

        if (res == null) {
            throw new AuraHandledException('No response from USCCB');
        }

        Integer status = res.getStatusCode();
        if (status < 200 || status >= 300) {
            throw new AuraHandledException('USCCB returned HTTP ' + status);
        }

        String html = res.getBody();
        if (String.isBlank(html)) {
            throw new AuraHandledException('USCCB returned empty content');
        }

        try {
            return parseGospelFromHtml(html);
        } catch (Exception e) {
            throw new AuraHandledException('Failed to parse USCCB Gospel: ' + e.getMessage());
        }
    }

    private static GospelResponse parseGospelFromHtml(String html) {
        // Normalize whitespace a bit, but keep structure markers.
        String source = html.replace('\r', '');

        // Find the Gospel section and stop before the next major section or footer area.
        Integer gospelHeadingPos = source.indexOf('### Gospel');
        if (gospelHeadingPos < 0) {
            throw new AuraHandledException('Could not find Gospel section');
        }

        Integer nextSectionPos = source.indexOf('### ', gospelHeadingPos + 1);
        Integer footerPos = source.indexOf('Readings for the Optional Memorial', gospelHeadingPos + 1);
        Integer endPos;

        if (nextSectionPos > -1 && footerPos > -1) {
            endPos = Math.min(nextSectionPos, footerPos);
        } else if (nextSectionPos > -1) {
            endPos = nextSectionPos;
        } else if (footerPos > -1) {
            endPos = footerPos;
        } else {
            endPos = source.length();
        }

        String gospelSection = source.substring(gospelHeadingPos, endPos);

        // Expected shape on page:
        // ### Gospel
        //
        // John 8:1-11
        //
        // Jesus went to the Mount...
        List<String> lines = new List<String>();
        for (String line : gospelSection.split('\n')) {
            String trimmed = line != null ? line.trim() : null;
            if (!String.isBlank(trimmed)) {
                lines.add(trimmed);
            }
        }

        if (lines.size() < 3) {
            throw new AuraHandledException('Gospel section was found but was incomplete');
        }

        String title = 'Gospel';
        String reference = lines[1];

        List<String> bodyLines = new List<String>();
        for (Integer i = 2; i < lines.size(); i++) {
            String line = lines[i];

            // Stop if page content starts drifting into other non-Gospel footer content.
            if (line.startsWith('* ') ||
                line.startsWith('LISTEN PODCAST') ||
                line.startsWith('VIEW REFLECTION VIDEO') ||
                line.startsWith('En Español') ||
                line.startsWith('View Calendar') ||
                line.startsWith('Get Daily Readings')) {
                break;
            }

            bodyLines.add(line);
        }

        String body = String.join(bodyLines, '\n\n');
        body = htmlDecode(body);

        if (String.isBlank(reference) || String.isBlank(body)) {
            throw new AuraHandledException('Could not extract Gospel reference/body');
        }

        return new GospelResponse(title, reference, body);
    }

    private static String htmlDecode(String input) {
        if (input == null) return null;

        String output = input;
        output = output.replace('&nbsp;', ' ');
        output = output.replace('&amp;', '&');
        output = output.replace('&quot;', '"');
        output = output.replace('&#39;', '\'');
        output = output.replace('&rsquo;', '\'');
        output = output.replace('&ldquo;', '"');
        output = output.replace('&rdquo;', '"');
        output = output.replace('&ndash;', '–');
        output = output.replace('&mdash;', '—');
        output = output.replace('&lt;', '<');
        output = output.replace('&gt;', '>');
        return output;
    }

    public class FlowInput {
        @InvocableVariable(required=false)
        public Date requestedDate;
    }

    public class FlowOutput {
        @InvocableVariable public String title;
        @InvocableVariable public String reference;
        @InvocableVariable public String body;
    }

    @InvocableMethod(
        label='Get Gospel of the Day'
        description='Fetches today’s Gospel from the official USCCB daily readings page'
    )
    public static List<FlowOutput> getGospelForFlow(List<FlowInput> inputs) {
        Date requestedDate = Date.today();
        if (inputs != null && !inputs.isEmpty() && inputs[0].requestedDate != null) {
            requestedDate = inputs[0].requestedDate;
        }

        GospelResponse gr = getGospelForDate(requestedDate);

        FlowOutput out = new FlowOutput();
        out.title = gr != null ? gr.title : null;
        out.reference = gr != null ? gr.reference : null;
        out.body = gr != null ? gr.body : null;

        return new List<FlowOutput>{ out };
    }
}