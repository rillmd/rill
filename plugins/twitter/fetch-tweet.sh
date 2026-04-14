#!/usr/bin/env bash
# fetch-tweet.sh — Deterministic tweet data extraction via FixTweet API
#
# Usage: fetch-tweet.sh <tweet-url>
#        fetch-tweet.sh <screen_name> <tweet_id>
#
# Output: Structured YAML to stdout
# Exit:   0=success, 1=bad args, 2=API failed, 3=parse error

set -euo pipefail

# --- Argument parsing ---

screen_name=""
tweet_id=""
url=""

if [ $# -eq 1 ]; then
    url="$1"
    if [[ "$url" =~ ^https?://(x\.com|twitter\.com)/([^/]+)/status/([0-9]+) ]]; then
        screen_name="${BASH_REMATCH[2]}"
        tweet_id="${BASH_REMATCH[3]}"
    else
        echo "Error: Not a valid tweet URL: $url" >&2
        exit 1
    fi
elif [ $# -eq 2 ]; then
    screen_name="$1"
    tweet_id="$2"
    url="https://x.com/${screen_name}/status/${tweet_id}"
else
    echo "Usage: fetch-tweet.sh <tweet-url>" >&2
    echo "       fetch-tweet.sh <screen_name> <tweet_id>" >&2
    exit 1
fi

# --- FixTweet API fetch ---

api_url="https://api.fxtwitter.com/${screen_name}/status/${tweet_id}"
api_json="$(curl -sL --max-time 15 "$api_url" 2>/dev/null)" || true

# Validate response
api_code=""
if [ -n "$api_json" ]; then
    api_code="$(echo "$api_json" | jq -r '.code // empty' 2>/dev/null)" || true
fi

if [ "$api_code" = "200" ]; then
    # --- Extract via jq and emit YAML ---
    echo "$api_json" | jq -r '
        .tweet as $t |

        # Author
        "tweet-author: \"@\($t.author.screen_name)\"",
        "tweet-author-name: \($t.author.name | @json)",
        "tweet-author-followers: \($t.author.followers // 0)",

        # Timestamps
        "tweet-date: \"\($t.created_at // "")\"",

        # Engagement
        "tweet-likes: \($t.likes // 0)",
        "tweet-retweets: \($t.retweets // 0)",
        "tweet-bookmarks: \($t.bookmarks // 0)",
        "tweet-views: \($t.views // 0)",

        # Engagement signals (deterministic)
        (
            ($t.bookmarks // 0) as $bm |
            ($t.likes // 0) as $lk |
            ($t.retweets // 0) as $rt |
            ($t.views // 0) as $vw |

            # bookmark/likes ratio (high = reference/tool value)
            (if $lk > 0 then (($bm * 100 / $lk) | floor | . / 100) else 0 end) as $bm_ratio |

            # engagement rate (likes+rt+bm / views * 100)
            (if $vw > 0 then ((($lk + $rt + $bm) * 10000 / $vw) | floor | . / 100) else 0 end) as $eng_rate |

            "engagement-save-ratio: \($bm_ratio)",
            "engagement-rate: \($eng_rate)"
        ),

        # Type
        "tweet-type: \(if $t.article then "article" else "tweet" end)",

        # Language
        "tweet-lang: \($t.lang // "und")",

        # Text (raw_text.text has t.co URLs; we output it and also provide expanded URLs separately)
        "text: |",
        ($t.text // "" | split("\n") | map("  " + .) | join("\n")),

        # URLs: extract from facets where type=url
        "urls:",
        (
            [$t.raw_text.facets // [] | .[] | select(.type == "url")]
            | if length == 0 then "  []"
              else .[] | "  - url: \(.replacement | @json)\n    display: \(.display // "" | @json)\n    original: \(.original // "" | @json)"
              end
        ),

        # Media
        (
            if ($t.media.all // [] | length) > 0 then
                "media:",
                (
                    $t.media.all[] |
                    "  - type: \(.type)",
                    "    url: \(.url // "" | @json)",
                    (if .thumbnail_url then "    thumbnail: \(.thumbnail_url | @json)" else empty end),
                    "    width: \(.width // 0)",
                    "    height: \(.height // 0)",
                    (if .duration then "    duration: \(.duration)" else empty end)
                )
            else empty
            end
        ),

        # Quote tweet
        (
            if $t.quote then
                "quote:",
                "  author: \"@\($t.quote.author.screen_name // "")\"",
                "  author-name: \($t.quote.author.name // "" | @json)",
                "  text: |",
                ($t.quote.text // "" | split("\n") | map("    " + .) | join("\n")),
                "  url: \"\($t.quote.url // "")\"",
                (
                    if ($t.quote.media.all // [] | length) > 0 then
                        "  media:",
                        ($t.quote.media.all[] |
                            "    - type: \(.type)",
                            "      url: \(.url // "" | @json)")
                    else empty end
                )
            else empty
            end
        ),

        # Article
        (
            if $t.article then
                "article:",
                "  title: \($t.article.title // "" | @json)",
                "  blocks:",
                (
                    $t.article.content.blocks[] |
                    "    - type: \(.type)",
                    "      text: \(.text // "" | @json)",
                    (
                        if (.inlineStyleRanges // [] | length) > 0 then
                            "      styles:",
                            (.inlineStyleRanges[] |
                                "        - style: \(.style)",
                                "          offset: \(.offset)",
                                "          length: \(.length)")
                        else empty end
                    ),
                    (
                        if (.entityRanges // [] | length) > 0 then
                            "      entities:",
                            (.entityRanges[] |
                                "        - key: \(.key)",
                                "          offset: \(.offset)",
                                "          length: \(.length)")
                        else empty end
                    )
                ),
                (
                    if ($t.article.content.entityMap // {} | length) > 0 then
                        "  entity-map:",
                        (
                            $t.article.content.entityMap | to_entries[] |
                            "    - key: \(.key | @json)",
                            "      type: \(.value.type // "")",
                            (if .value.data.url then "      url: \(.value.data.url | @json)" else empty end),
                            (if .value.data.tweetId then "      tweet-id: \"\(.value.data.tweetId)\"" else empty end)
                        )
                    else empty end
                )
            else empty
            end
        ),

        # Source indicator
        "source: fxtwitter"
    ' 2>/dev/null

    jq_exit=$?
    if [ "$jq_exit" -ne 0 ]; then
        echo "Error: jq parse failed for tweet $tweet_id" >&2
        exit 3
    fi
    exit 0
fi

# --- oEmbed fallback ---

echo "FixTweet API failed (code: ${api_code:-empty}), trying oEmbed..." >&2

oembed_url="https://publish.twitter.com/oembed?url=${url}"
oembed_json="$(curl -sL --max-time 10 "$oembed_url" 2>/dev/null)" || true

if [ -n "$oembed_json" ]; then
    oembed_html="$(echo "$oembed_json" | jq -r '.html // empty' 2>/dev/null)" || true
    oembed_author="$(echo "$oembed_json" | jq -r '.author_name // empty' 2>/dev/null)" || true
    oembed_author_url="$(echo "$oembed_json" | jq -r '.author_url // empty' 2>/dev/null)" || true

    if [ -n "$oembed_html" ]; then
        # Extract text from <p> tags, strip HTML
        oembed_text="$(echo "$oembed_html" | sed -n 's/.*<p[^>]*>\(.*\)<\/p>.*/\1/p' | sed 's/<[^>]*>//g' | head -1)"

        # Extract screen_name from author_url
        oembed_screen=""
        if [[ "$oembed_author_url" =~ /([^/]+)$ ]]; then
            oembed_screen="${BASH_REMATCH[1]}"
        fi

        cat <<YAML
tweet-author: "@${oembed_screen:-${screen_name}}"
tweet-author-name: "${oembed_author}"
tweet-author-followers: 0
tweet-date: ""
tweet-likes: 0
tweet-retweets: 0
tweet-bookmarks: 0
tweet-views: 0
tweet-type: tweet
tweet-lang: und
text: |
  ${oembed_text}
urls: []
source: oembed
YAML
        exit 0
    fi
fi

echo "Error: Both FixTweet and oEmbed failed for $url" >&2
exit 2
