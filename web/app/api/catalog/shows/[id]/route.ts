import { NextResponse } from "next/server";
import { catalogShow } from "@/lib/tmdb";

export async function GET(request: Request, context: { params: Promise<{ id: string }> }) {
  const { id: rawID } = await context.params;
  const id = Number(rawID);
  if (!Number.isInteger(id) || id <= 0) {
    return NextResponse.json({ error: "Invalid show ID." }, { status: 400 });
  }
  const language = new URL(request.url).searchParams.get("language")?.trim() || "en-US";
  try {
    return NextResponse.json(await catalogShow(id, language));
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Unable to load that series." },
      { status: 502 },
    );
  }
}
