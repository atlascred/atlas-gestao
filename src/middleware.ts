import {NextRequest,NextResponse} from 'next/server';
import {createServerClient,type CookieOptions} from '@supabase/ssr';
export async function middleware(request:NextRequest){
 const mutation=!['GET','HEAD','OPTIONS'].includes(request.method);
 if(mutation&&request.nextUrl.pathname.startsWith('/api/')){
  const origin=request.headers.get('origin');const expected=process.env.NEXT_PUBLIC_SITE_URL;
  const allowed=new Set([request.nextUrl.origin,...(expected?[expected.replace(/\/$/,'')]:[])]);
  if((origin&&!allowed.has(origin))||request.headers.get('sec-fetch-site')==='cross-site')return NextResponse.json({error:'Origem da solicitação não permitida.'},{status:403});
 }
 let response=NextResponse.next({request});
 if(process.env.NEXT_PUBLIC_SUPABASE_URL&&process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY){
  const db=createServerClient(process.env.NEXT_PUBLIC_SUPABASE_URL,process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,{cookies:{getAll:()=>request.cookies.getAll(),setAll:(values:{name:string;value:string;options:CookieOptions}[])=>{
   values.forEach(({name,value})=>request.cookies.set(name,value));response=NextResponse.next({request});values.forEach(({name,value,options})=>response.cookies.set(name,value,options));
  }}});
  const {data:{user}}=await db.auth.getUser();
  if(user?.user_metadata?.must_change_password){
   const path=request.nextUrl.pathname,allowed=path==='/login'||path==='/trocar-senha'||path==='/api/local-auth'||path==='/api/account/password';
   if(!allowed){const blocked=path.startsWith('/api/')?NextResponse.json({error:'Troque a senha inicial antes de usar o sistema.',code:'password_change_required'},{status:403}):NextResponse.redirect(new URL('/trocar-senha',request.url));response.cookies.getAll().forEach(cookie=>blocked.cookies.set(cookie));blocked.headers.set('Cache-Control','private, no-store');blocked.headers.set('X-Content-Type-Options','nosniff');blocked.headers.set('X-Frame-Options','DENY');blocked.headers.set('Referrer-Policy','same-origin');return blocked;}
  }
 }
 response.headers.set('X-Content-Type-Options','nosniff');response.headers.set('X-Frame-Options','DENY');response.headers.set('Referrer-Policy','same-origin');response.headers.set('Permissions-Policy','camera=(), microphone=(), geolocation=()');
 if(request.nextUrl.pathname.startsWith('/api/'))response.headers.set('Cache-Control','private, no-store');
 return response;
}
export const config={matcher:['/((?!_next/static|_next/image|favicon.ico|logoatlas.png|logonovo.png).*)']};
