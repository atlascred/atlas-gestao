import {createHash} from 'node:crypto';
import {NextRequest,NextResponse} from 'next/server';
import {z} from 'zod';
import {createSupabaseAdmin} from '@/lib/supabase/admin';
import {checkRateLimit} from '@/lib/rate-limit';

export async function POST(req:NextRequest){
 const parsed=z.object({trackingCode:z.string().trim().min(12).max(64)}).safeParse(await req.json().catch(()=>null));
 if(!parsed.success)return NextResponse.json({error:'Informe o código de acompanhamento.'},{status:422});
 try{
  if(!await checkRateLimit(req,'tenant-request-status',12,900))return NextResponse.json({error:'Muitas consultas deste endereço. Tente novamente em 15 minutos.'},{status:429,headers:{'Retry-After':'900'}});
  const tokenHash=createHash('sha256').update(parsed.data.trackingCode).digest('hex');
  const {data,error}=await createSupabaseAdmin().rpc('lookup_tenant_application',{p_status_token_hash:tokenHash});
  if(error)throw error;
  if(!data)return NextResponse.json({error:'Código inválido ou solicitação não encontrada.'},{status:404});
  return NextResponse.json({data});
 }catch{return NextResponse.json({error:'Não foi possível consultar o andamento agora.'},{status:503});}
}
