use slint::Image;

macro_rules! svg_icon {
    ($name:literal) => {
        Image::load_from_svg_data(include_bytes!(concat!(
            "../assets/providers/ProviderIcon-",
            $name,
            ".svg"
        )))
        .unwrap_or_default()
    };
}

pub fn provider_icon(provider_id: &str, resource_name: Option<&str>) -> Image {
    let resource = resource_name
        .and_then(|name| name.strip_prefix("ProviderIcon-"))
        .unwrap_or(provider_id);
    let resource = match resource {
        "openai" | "azureopenai" => "codex",
        "alibabatokenplan" => "alibaba",
        "moonshot" => "kimi",
        other => other,
    };

    match resource {
        "abacus" => svg_icon!("abacus"),
        "aiand" => svg_icon!("aiand"),
        "alibaba" => svg_icon!("alibaba"),
        "amp" => svg_icon!("amp"),
        "antigravity" => svg_icon!("antigravity"),
        "augment" => svg_icon!("augment"),
        "bedrock" => svg_icon!("bedrock"),
        "chutes" => svg_icon!("chutes"),
        "claude" => svg_icon!("claude"),
        "clawrouter" => svg_icon!("clawrouter"),
        "clinepass" => svg_icon!("clinepass"),
        "codebuff" => svg_icon!("codebuff"),
        "codex" => svg_icon!("codex"),
        "commandcode" => svg_icon!("commandcode"),
        "copilot" => svg_icon!("copilot"),
        "crof" => svg_icon!("crof"),
        "cursor" => svg_icon!("cursor"),
        "deepgram" => svg_icon!("deepgram"),
        "deepinfra" => svg_icon!("deepinfra"),
        "deepseek" => svg_icon!("deepseek"),
        "devin" => svg_icon!("devin"),
        "doubao" => svg_icon!("doubao"),
        "elevenlabs" => svg_icon!("elevenlabs"),
        "factory" => svg_icon!("factory"),
        "fireworks" => svg_icon!("fireworks"),
        "gemini" => svg_icon!("gemini"),
        "grok" => svg_icon!("grok"),
        "groq" => svg_icon!("groq"),
        "ibmbob" => svg_icon!("ibmbob"),
        "jetbrains" => svg_icon!("jetbrains"),
        "kilo" => svg_icon!("kilo"),
        "kimi" => svg_icon!("kimi"),
        "kiro" => svg_icon!("kiro"),
        "litellm" => svg_icon!("litellm"),
        "llmproxy" => svg_icon!("llmproxy"),
        "longcat" => svg_icon!("longcat"),
        "manus" => svg_icon!("manus"),
        "mimo" => svg_icon!("mimo"),
        "minimax" => svg_icon!("minimax"),
        "mistral" => svg_icon!("mistral"),
        "neuralwatt" => svg_icon!("neuralwatt"),
        "notion" => svg_icon!("notion"),
        "ollama" => svg_icon!("ollama"),
        "opencode" => svg_icon!("opencode"),
        "opencodego" => svg_icon!("opencodego"),
        "openrouter" => svg_icon!("openrouter"),
        "perplexity" => svg_icon!("perplexity"),
        "poe" => svg_icon!("poe"),
        "qoder" => svg_icon!("qoder"),
        "qwencloud" => svg_icon!("qwencloud"),
        "sakana" => svg_icon!("sakana"),
        "stepfun" => svg_icon!("stepfun"),
        "sub2api" => svg_icon!("sub2api"),
        "synthetic" => svg_icon!("synthetic"),
        "t3chat" => svg_icon!("t3chat"),
        "venice" => svg_icon!("venice"),
        "vertexai" => svg_icon!("vertexai"),
        "warp" => svg_icon!("warp"),
        "wayfinder" => svg_icon!("wayfinder"),
        "windsurf" => svg_icon!("windsurf"),
        "xai" => svg_icon!("xai"),
        "zai" => svg_icon!("zai"),
        "zed" => svg_icon!("zed"),
        "zenmux" => svg_icon!("zenmux"),
        "zoommate" => svg_icon!("zoommate"),
        _ => Image::default(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const PROVIDER_IDS: &[&str] = &[
        "codex",
        "openai",
        "azureopenai",
        "claude",
        "clinepass",
        "cursor",
        "opencode",
        "opencodego",
        "alibaba",
        "alibabatokenplan",
        "qwencloud",
        "factory",
        "fireworks",
        "gemini",
        "antigravity",
        "copilot",
        "devin",
        "zai",
        "minimax",
        "manus",
        "kimi",
        "kilo",
        "kiro",
        "vertexai",
        "augment",
        "jetbrains",
        "moonshot",
        "amp",
        "t3chat",
        "ollama",
        "synthetic",
        "openrouter",
        "elevenlabs",
        "warp",
        "windsurf",
        "zed",
        "perplexity",
        "mimo",
        "doubao",
        "sakana",
        "abacus",
        "mistral",
        "deepseek",
        "deepinfra",
        "codebuff",
        "crof",
        "venice",
        "commandcode",
        "qoder",
        "stepfun",
        "bedrock",
        "grok",
        "groq",
        "llmproxy",
        "litellm",
        "deepgram",
        "poe",
        "chutes",
        "neuralwatt",
        "clawrouter",
        "longcat",
        "sub2api",
        "wayfinder",
        "zenmux",
        "aiand",
        "zoommate",
        "xai",
        "notion",
        "ibmbob",
    ];

    #[test]
    fn every_canonical_provider_has_embedded_artwork() {
        assert_eq!(PROVIDER_IDS.len(), 69);
        for provider_id in PROVIDER_IDS {
            let size = provider_icon(provider_id, None).size();
            assert!(
                size.width > 0 && size.height > 0,
                "missing provider artwork for {provider_id}"
            );
        }
    }
}
