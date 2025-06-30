import { prismaClient } from "db/client";
import { NextResponse } from 'next/server';

export async function GET() {
  try {
    const users = await prismaClient.user.findMany();
    return NextResponse.json(users);
  } catch (error) {
    console.error('Database error:', error);
    return NextResponse.json(
      { error: 'Failed to fetch users' },
      { status: 500 }
    );
  }
}