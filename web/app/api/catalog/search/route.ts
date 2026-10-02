import { NextResponse } from "next/server";
import { searchCatalog } from "@/lib/tmdb";

export async function GET(request: Request) {
  const url = new URL(request.url);
  const query = url.searchParams.get("q")?.trim() ?? "";
  const language = url.searchParams.get("language")?.trim() || "en-US";
  if (query.length < 2) return NextResponse.json({ results: [] });
  try {
    return NextResponse.json({ results: await searchCatalog(query, language) });
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Catalog search failed." },
      { status: 502 },
    );
  }
}
