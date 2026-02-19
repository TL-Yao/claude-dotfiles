import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { ReaderClient } from "@vakra-dev/reader";
import type { ScrapeResult, CrawlResult } from "@vakra-dev/reader";

// ---------------------------------------------------------------------------
// Singleton ReaderClient (lazy init on first tool call)
// ---------------------------------------------------------------------------

let client: ReaderClient | null = null;
let initPromise: Promise<ReaderClient> | null = null;

async function getClient(): Promise<ReaderClient> {
  if (client?.isReady()) return client;

  if (initPromise) return initPromise;

  initPromise = (async () => {
    client = new ReaderClient({
      browserPool: { size: 1, retireAfterPages: 50, retireAfterMinutes: 15 },
    });
    await client.start();
    return client;
  })();

  return initPromise;
}

// Content truncation to avoid blowing up context window
const MAX_CONTENT_LENGTH = 80_000;

function truncate(text: string, limit = MAX_CONTENT_LENGTH): string {
  if (text.length <= limit) return text;
  return text.slice(0, limit) + `\n\n[... truncated at ${limit} chars, total ${text.length} chars]`;
}

// ---------------------------------------------------------------------------
// MCP Server
// ---------------------------------------------------------------------------

const server = new McpServer({
  name: "reader-mcp",
  version: "1.0.0",
});

// ---------------------------------------------------------------------------
// Tool: reader_scrape
// ---------------------------------------------------------------------------

server.tool(
  "reader_scrape",
  "Scrape one or more URLs and return clean markdown content. Use this when WebFetch fails (403, Cloudflare block, JS-rendered SPA) or when you need high-quality content extraction.",
  {
    urls: z.array(z.string().url()).min(1).describe("URLs to scrape"),
    onlyMainContent: z
      .boolean()
      .optional()
      .default(true)
      .describe("Extract only main content, removing nav/header/footer (default: true)"),
    includeTags: z
      .array(z.string())
      .optional()
      .describe("CSS selectors to include (e.g. ['article', '.post-content'])"),
    excludeTags: z
      .array(z.string())
      .optional()
      .describe("CSS selectors to exclude (e.g. ['.sidebar', '.ads'])"),
    waitForSelector: z
      .string()
      .optional()
      .describe("CSS selector to wait for before extracting (useful for JS-rendered pages)"),
  },
  async (params) => {
    try {
      const reader = await getClient();

      const result: ScrapeResult = await reader.scrape({
        urls: params.urls,
        formats: ["markdown"],
        onlyMainContent: params.onlyMainContent,
        includeTags: params.includeTags,
        excludeTags: params.excludeTags,
        waitForSelector: params.waitForSelector,
        timeoutMs: 60_000,
        batchConcurrency: Math.min(params.urls.length, 3),
      });

      // Format output
      const parts: string[] = [];

      for (const item of result.data) {
        const md = item.markdown ?? "";
        const title = item.metadata.website?.title ?? "Untitled";
        const url = item.metadata.baseUrl;
        const duration = item.metadata.duration;

        parts.push(
          `## ${title}\n**URL:** ${url}\n**Fetched in:** ${duration}ms\n\n${truncate(md)}`
        );
      }

      // Append batch errors if any
      if (result.batchMetadata.errors?.length) {
        parts.push(
          `## Errors\n${result.batchMetadata.errors.map((e) => `- ${e.url}: ${e.error}`).join("\n")}`
        );
      }

      const summary = `Scraped ${result.batchMetadata.successfulUrls}/${result.batchMetadata.totalUrls} URLs in ${result.batchMetadata.totalDuration}ms`;

      return {
        content: [{ type: "text", text: `${summary}\n\n${parts.join("\n\n---\n\n")}` }],
      };
    } catch (err: any) {
      return {
        content: [{ type: "text", text: `Scrape failed: ${err.message}` }],
        isError: true,
      };
    }
  }
);

// ---------------------------------------------------------------------------
// Tool: reader_crawl
// ---------------------------------------------------------------------------

server.tool(
  "reader_crawl",
  "Crawl a website to discover URLs and optionally scrape their content. Useful for understanding site structure or bulk content extraction.",
  {
    url: z.string().url().describe("Seed URL to start crawling from"),
    depth: z.number().int().min(1).max(5).optional().default(1).describe("Max crawl depth (default: 1, max: 5)"),
    maxPages: z
      .number()
      .int()
      .min(1)
      .max(50)
      .optional()
      .default(10)
      .describe("Max pages to discover (default: 10, max: 50)"),
    scrape: z
      .boolean()
      .optional()
      .default(false)
      .describe("Also scrape content of discovered pages (default: false)"),
    includePatterns: z
      .array(z.string())
      .optional()
      .describe("URL regex patterns to include (e.g. ['/docs/', '/blog/'])"),
    excludePatterns: z
      .array(z.string())
      .optional()
      .describe("URL regex patterns to exclude (e.g. ['/login', '/admin'])"),
  },
  async (params) => {
    try {
      const reader = await getClient();

      const result: CrawlResult = await reader.crawl({
        url: params.url,
        depth: params.depth,
        maxPages: params.maxPages,
        scrape: params.scrape,
        includePatterns: params.includePatterns,
        excludePatterns: params.excludePatterns,
        delayMs: 500,
        formats: ["markdown"],
      });

      const parts: string[] = [];

      // URL list
      parts.push("## Discovered URLs\n");
      for (const u of result.urls) {
        const desc = u.description ? ` - ${u.description}` : "";
        parts.push(`- [${u.title}](${u.url})${desc}`);
      }

      // Scraped content
      if (result.scraped) {
        parts.push("\n## Scraped Content\n");
        for (const item of result.scraped.data) {
          const md = item.markdown ?? "";
          const title = item.metadata.website?.title ?? "Untitled";
          const url = item.metadata.baseUrl;
          parts.push(`### ${title}\n**URL:** ${url}\n\n${truncate(md)}`);
        }
      }

      const summary = `Crawled ${result.metadata.totalUrls} URLs from ${result.metadata.seedUrl} (depth: ${result.metadata.maxDepth}) in ${result.metadata.totalDuration}ms`;

      return {
        content: [{ type: "text", text: `${summary}\n\n${parts.join("\n")}` }],
      };
    } catch (err: any) {
      return {
        content: [{ type: "text", text: `Crawl failed: ${err.message}` }],
        isError: true,
      };
    }
  }
);

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((err) => {
  console.error("Failed to start reader-mcp:", err);
  process.exit(1);
});
