import type { Metadata } from "next";
import "./globals.css";
export const metadata: Metadata = { title: "Sim2Seoul", description: "서울의 거리를 탐험하고 함께 걷는 개발 중인 시뮬레이션." };
export default function RootLayout({children}: Readonly<{children: React.ReactNode}>) { return <html lang="ko"><body>{children}</body></html>; }
