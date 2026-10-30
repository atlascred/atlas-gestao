import type { Metadata } from 'next';
import './globals.css';
export const metadata: Metadata = { title: 'ATLAS | Gestão de empréstimos', description: 'Gestão de clientes, empréstimos e operação financeira.', manifest:'/manifest.webmanifest', appleWebApp:{capable:true,statusBarStyle:'default',title:'ATLAS'} };
export default function RootLayout({ children }: Readonly<{children: React.ReactNode}>) { return <html lang="pt-BR"><body>{children}</body></html>; }
