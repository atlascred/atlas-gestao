import { createServerClient, type SetAllCookies } from '@supabase/ssr';
import { cookies } from 'next/headers';
export function supabaseReady(){return Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL&&process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY)}
export async function createSupabaseServer(){
 const jar=await cookies();
 return createServerClient(process.env.NEXT_PUBLIC_SUPABASE_URL!,process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,{cookies:{getAll(){return jar.getAll()},setAll(values:SetAllCookies extends (arg:infer T)=>unknown?T:never){try{values.forEach(({name,value,options})=>jar.set(name,value,options))}catch{}}}});
}
export async function tenantContext(){
 if(!supabaseReady())return {supabase:null,user:null,tenantId:null,tenantName:null,role:null,error:'Supabase não configurado.'} as const;
 const supabase=await createSupabaseServer(); const {data:{user},error}=await supabase.auth.getUser();
 if(error||!user)return {supabase,user:null,tenantId:null,tenantName:null,role:null,error:'Sessão inválida.'} as const;
 const {data:memberships,error:membershipError}=await supabase.from('memberships').select('tenant_id,role,tenants!inner(state,name)').eq('user_id',user.id).eq('active',true).eq('tenants.state','approved').limit(100);
 const jar=await cookies();const selected=jar.get('atlas_active_tenant')?.value;const membership=selected?memberships?.find(m=>m.tenant_id===selected):memberships?.length===1?memberships[0]:null;
 if(membershipError||!membership)return {supabase,user,tenantId:null,tenantName:null,role:null,error:'Selecione uma empresa aprovada ou solicite acesso.'} as const;
 const relation=membership.tenants as unknown as {name:string}|{name:string}[];
 return {supabase,user,tenantId:membership.tenant_id,tenantName:(Array.isArray(relation)?relation[0]:relation)?.name||null,role:membership.role,error:null} as const;
}
