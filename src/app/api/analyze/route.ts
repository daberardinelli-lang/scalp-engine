import { NextRequest, NextResponse } from 'next/server';
import { analyzeChart } from '@/lib/ai/analyze';
import type { AIProvider } from '@/lib/types';

export const maxDuration = 60;

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { image, mimeType, provider } = body as {
      image: string;
      mimeType: string;
      provider: AIProvider;
    };

    if (!image || !provider) {
      return NextResponse.json(
        { error: 'Missing required fields: image, provider' },
        { status: 400 },
      );
    }

    const validProviders: AIProvider[] = ['claude', 'gemini'];
    if (!validProviders.includes(provider)) {
      return NextResponse.json(
        { error: 'Invalid provider. Use "claude" or "gemini"' },
        { status: 400 },
      );
    }

    const result = await analyzeChart(
      image,
      mimeType || 'image/png',
      provider,
    );

    return NextResponse.json(result);
  } catch (error) {
    console.error('[API /analyze] Error:', error);
    return NextResponse.json(
      {
        error: error instanceof Error ? error.message : 'Analysis failed',
      },
      { status: 500 },
    );
  }
}
