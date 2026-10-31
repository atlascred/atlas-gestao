import { NextResponse } from 'next/server';
import { tenantContext,createSupabaseServer,supabaseReady } from '@/lib/supabase/server';
export async function requireTenant(roles?:string[],permission?:string){
 const ctx=await tenantContext();
 if(!ctx.user)return {response:NextResponse.json({error:ctx.error},{status:ctx.error==='Supabase não configurado.'?503:401})} as const;
 if(ctx.user.user_metadata?.must_change_password)return {response:NextResponse.json({error:'Troque a senha inicial antes de usar o sistema.',code:'password_change_required'},{status:403})} as const;
 if(!ctx.tenantId||!ctx.role)return {response:NextResponse.json({error:ctx.error||'Acesso negado.'},{status:403})} as const;
 if(roles&&!roles.includes(ctx.role))return {response:NextResponse.json({error:'Você não tem autorização para esta ação.'},{status:403})} as const;
 if(ctx.role==='employee'&&permission){const {data}=await ctx.supabase!.from('memberships').select('permissions').eq('tenant_id',ctx.tenantId).eq('user_id',ctx.user.id).maybeSingle();const permissions=data?.permissions as Record<string,boolean>|null;if(!permissions?.all&&!permissions?.[permission])return {response:NextResponse.json({error:'Este funcionário não possui a permissão necessária.'},{status:403})} as const;}
 return {ctx} as const;
}
export function errorResponse(message:string,status=400){return NextResponse.json({error:message},{status});}

export async function requireMasterAdmin(){if(!supabaseReady())return {response:NextResponse.json({error:'Supabase não configurado.'},{status:503})} as const;const supabase=await createSupabaseServer();const {data:{user}}=await supabase.auth.getUser();if(!user)return {response:NextResponse.json({error:'Sessão inválida.'},{status:401})} as const;if(user.user_metadata?.must_change_password)return {response:NextResponse.json({error:'Troque a senha inicial antes de usar o sistema.',code:'password_change_required'},{status:403})} as const;const {data,error}=await supabase.rpc('is_master_admin');if(error||!data)return {response:NextResponse.json({error:'Acesso exclusivo ao master admin.'},{status:403})} as const;return {ctx:{supabase,user,tenantId:null,tenantName:null,role:'master_admin' as const,error:null}} as const;}
