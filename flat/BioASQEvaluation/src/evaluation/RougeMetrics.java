/*
 * ROUGE-2 and ROUGE-SU4 for ideal answer evaluation (Phase B).
 * S = system ideal answer, Refs = golden ideal answer (one ref per question).
 */
package evaluation;

import java.util.HashMap;
import java.util.Map;
import java.util.regex.Pattern;

public final class RougeMetrics {

    private static final Pattern TOKENIZE = Pattern.compile("\\s+");

    private RougeMetrics() {}

    /**
     * Tokenize: split on whitespace, lowercase. Non-alphanumeric stripped for consistency.
     */
    private static String[] tokenize(String text) {
        if (text == null || text.isEmpty()) return new String[0];
        String normalized = text.toLowerCase().trim().replaceAll("[^a-z0-9\\s]", " ");
        String[] tokens = TOKENIZE.split(normalized);
        if (tokens.length == 1 && tokens[0].isEmpty()) return new String[0];
        return tokens;
    }

    /**
     * Build bigram count map: key = "w1 w2", value = count.
     */
    private static Map<String, Integer> bigrams(String[] tokens) {
        Map<String, Integer> map = new HashMap<>();
        for (int i = 0; i + 1 < tokens.length; i++) {
            String key = tokens[i] + " " + tokens[i + 1];
            map.put(key, map.getOrDefault(key, 0) + 1);
        }
        return map;
    }

    /**
     * ROUGE-2 Recall: (sum over ref bigrams of min(S,R)) / (total bigrams in R).
     */
    public static double rouge2Recall(String system, String ref) {
        String[] sTokens = tokenize(system);
        String[] rTokens = tokenize(ref);
        if (rTokens.length < 2) return Double.NaN;
        Map<String, Integer> sBigrams = bigrams(sTokens);
        Map<String, Integer> rBigrams = bigrams(rTokens);
        int match = 0;
        int refTotal = 0;
        for (Map.Entry<String, Integer> e : rBigrams.entrySet()) {
            int rCount = e.getValue();
            refTotal += rCount;
            match += Math.min(rCount, sBigrams.getOrDefault(e.getKey(), 0));
        }
        if (refTotal == 0) return Double.NaN;
        return (double) match / refTotal;
    }

    /**
     * ROUGE-2 Precision: (sum over ref bigrams of min(S,R)) / (total bigrams in S).
     */
    public static double rouge2Precision(String system, String ref) {
        String[] sTokens = tokenize(system);
        String[] rTokens = tokenize(ref);
        if (sTokens.length < 2) return Double.NaN;
        Map<String, Integer> sBigrams = bigrams(sTokens);
        Map<String, Integer> rBigrams = bigrams(rTokens);
        int match = 0;
        int sysTotal = 0;
        for (Map.Entry<String, Integer> e : sBigrams.entrySet()) {
            int sCount = e.getValue();
            sysTotal += sCount;
            match += Math.min(sCount, rBigrams.getOrDefault(e.getKey(), 0));
        }
        if (sysTotal == 0) return Double.NaN;
        return (double) match / sysTotal;
    }

    /**
     * ROUGE-2 F1: 2*P*R/(P+R). Returns NaN when undefined.
     */
    public static double rouge2F1(String system, String ref) {
        double r = rouge2Recall(system, ref);
        double p = rouge2Precision(system, ref);
        if (Double.isNaN(r) || Double.isNaN(p) || (p + r == 0)) return Double.NaN;
        return 2.0 * p * r / (p + r);
    }

    /**
     * Skip bigrams with max gap 4: pairs (w_i, w_j) with i < j and j - i - 1 <= 4 (so j - i <= 5).
     * Key format "w_i|w_j".
     */
    private static Map<String, Integer> skipBigrams(String[] tokens, int maxGap) {
        Map<String, Integer> map = new HashMap<>();
        for (int i = 0; i < tokens.length; i++) {
            for (int j = i + 1; j < tokens.length && (j - i - 1) <= maxGap; j++) {
                String key = tokens[i] + "|" + tokens[j];
                map.put(key, map.getOrDefault(key, 0) + 1);
            }
        }
        return map;
    }

    private static Map<String, Integer> unigrams(String[] tokens) {
        Map<String, Integer> map = new HashMap<>();
        for (String t : tokens) {
            if (t.isEmpty()) continue;
            map.put(t, map.getOrDefault(t, 0) + 1);
        }
        return map;
    }

    /**
     * ROUGE-SU4: unigrams + skip bigrams (max gap 4). Recall = matching / (total in R).
     */
    public static double rougeSu4Recall(String system, String ref) {
        String[] sTokens = tokenize(system);
        String[] rTokens = tokenize(ref);
        if (rTokens.length == 0) return Double.NaN;
        Map<String, Integer> sUni = unigrams(sTokens);
        Map<String, Integer> rUni = unigrams(rTokens);
        Map<String, Integer> sSkip = skipBigrams(sTokens, 4);
        Map<String, Integer> rSkip = skipBigrams(rTokens, 4);
        int match = 0;
        for (Map.Entry<String, Integer> e : rUni.entrySet())
            match += Math.min(e.getValue(), sUni.getOrDefault(e.getKey(), 0));
        for (Map.Entry<String, Integer> e : rSkip.entrySet())
            match += Math.min(e.getValue(), sSkip.getOrDefault(e.getKey(), 0));
        int refTotal = 0;
        for (int c : rUni.values()) refTotal += c;
        for (int c : rSkip.values()) refTotal += c;
        if (refTotal == 0) return Double.NaN;
        return (double) match / refTotal;
    }

    /**
     * ROUGE-SU4 Precision: matching / (total in S).
     */
    public static double rougeSu4Precision(String system, String ref) {
        String[] sTokens = tokenize(system);
        String[] rTokens = tokenize(ref);
        if (sTokens.length == 0) return Double.NaN;
        Map<String, Integer> sUni = unigrams(sTokens);
        Map<String, Integer> rUni = unigrams(rTokens);
        Map<String, Integer> sSkip = skipBigrams(sTokens, 4);
        Map<String, Integer> rSkip = skipBigrams(rTokens, 4);
        int match = 0;
        for (Map.Entry<String, Integer> e : sUni.entrySet())
            match += Math.min(e.getValue(), rUni.getOrDefault(e.getKey(), 0));
        for (Map.Entry<String, Integer> e : sSkip.entrySet())
            match += Math.min(e.getValue(), rSkip.getOrDefault(e.getKey(), 0));
        int sysTotal = 0;
        for (int c : sUni.values()) sysTotal += c;
        for (int c : sSkip.values()) sysTotal += c;
        if (sysTotal == 0) return Double.NaN;
        return (double) match / sysTotal;
    }

    /**
     * ROUGE-SU4 F1: 2*P*R/(P+R).
     */
    public static double rougeSu4F1(String system, String ref) {
        double r = rougeSu4Recall(system, ref);
        double p = rougeSu4Precision(system, ref);
        if (Double.isNaN(r) || Double.isNaN(p) || (p + r == 0)) return Double.NaN;
        return 2.0 * p * r / (p + r);
    }
}
