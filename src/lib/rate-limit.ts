import {createHmac} from 'node:crypto';
import {createSupabaseAdmin} from '@/lib/supabase/admin';

export async function checkRateLimit(request:Request,scope:string,limit:number,windowSeconds=900){
 const secret=process.env.RATE_LIMIT_SECRET;
 if(!secret)throw new Error('Rate limit secret is not configured.');
 const ip=request.headers.get('x-real-ip')||request.headers.get('x-forwarded-for')?.split(',')[0]?.trim()||'unknown';
 const keyHash=createHmac('sha256',secret).update(`${scope}:${ip}`).digest('hex');
 const {data,error}=await createSupabaseAdmin().rpc('consume_api_rate_limit',{p_key_hash:keyHash,p_limit:limit,p_window_seconds:windowSeconds});
 if(error)throw error;
 return Boolean(data);
}
