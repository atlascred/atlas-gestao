import {NextRequest,NextResponse} from 'next/server';
import {z} from 'zod';
import {requireTenant} from '@/lib/api';
export async function PATCH(req:NextRequest,{params}:{params:Promise<{id:string}>}){
 const r=await requireTenant(['master_admin','tenant_admin']);if('response'in r)return r.response;
 const id=(await params).id;
 const p=z.object({active:z.boolean(),role:z.enum(['tenant_admin','employee','collector']).optional(),permissions:z.record(z.string(),z.boolean()).optional()}).safeParse(await req.json().catch(()=>null));
 if(!z.uuid().safeParse(id).success||!p.success)return NextResponse.json({error:'Atualização inválida.'},{status:422});
 const {error}=await r.ctx.supabase!.rpc('update_tenant_membership',{p_tenant:r.ctx.tenantId,p_membership:id,p_active:p.data.active,p_role:p.data.role||null,p_permissions:p.data.permissions||null});
 if(error)return NextResponse.json({error:error.message.includes('last_admin')?'A empresa precisa manter pelo menos um administrador ativo.':'Não foi possível atualizar o usuário.'},{status:error.message.includes('last_admin')?409:400});
 return NextResponse.json({ok:true});
}
