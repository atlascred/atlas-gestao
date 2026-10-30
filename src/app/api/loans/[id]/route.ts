import {NextResponse} from 'next/server';
import {requireTenant} from '@/lib/api';
export async function GET(_req:Request,{params}:{params:Promise<{id:string}>}){
 const auth=await requireTenant(['tenant_admin','master_admin','employee'],'loans.read');if('response'in auth)return auth.response;
 const {id}=await params;const db=auth.ctx.supabase!;
 const {data:loan,error}=await db.from('loans').select('*,clients(full_name)').eq('tenant_id',auth.ctx.tenantId!).eq('id',id).maybeSingle();
 if(error||!loan)return NextResponse.json({error:'Contrato não encontrado.'},{status:404});
 const [parts,fees,payments]=await Promise.all([db.from('installments').select('*').eq('tenant_id',auth.ctx.tenantId!).eq('loan_id',id).order('sequence'),db.from('loan_fee_charges').select('*').eq('tenant_id',auth.ctx.tenantId!).eq('loan_id',id).order('charge_date'),db.from('payments').select('id,amount,payment_kind,paid_at,reversed_at,note').eq('tenant_id',auth.ctx.tenantId!).eq('loan_id',id).order('paid_at',{ascending:false})]);
 if(parts.error||fees.error||payments.error)return NextResponse.json({error:'Não foi possível consultar o histórico.'},{status:403});
 const installments=parts.data||[],charges=fees.data||[];
 // Project charges without modifying state on GET. Receipt recomputes under a row lock.
 const today=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Sao_Paulo'}).format(new Date());
 const cursor=new Date((loan.fees_assessed_through||loan.start_date)+'T00:00:00Z');cursor.setUTCDate(cursor.getUTCDate()+1);
 let days=Number(loan.delinquent_days||0);const pending=[];
 while(cursor.toISOString().slice(0,10)<=today&&loan.state==='active'){
  const day=cursor.toISOString().slice(0,10);const affected=installments.filter(i=>i.state!=='cancelled'&&i.due_date<day&&Number(i.amount)>Number(i.paid_amount)+Number(i.waived_amount));
  let amount=0;
  if(affected.length){if(loan.modality==='daily'){days++;if(days%Number(loan.late_fee_block_days)===0)amount=Number(loan.late_fee);}else amount=Number(loan.late_fee)*affected.length;}else days=0;
  if(amount>0)pending.push({charge_date:day,amount,calculation:{unpaid_installments:affected.length,block_days:loan.late_fee_block_days},projected:true});
  cursor.setUTCDate(cursor.getUTCDate()+1);
 }
 const principalBalance=installments.filter(i=>i.state!=='cancelled').reduce((a,i)=>a+Number(i.amount)-Number(i.paid_amount)-Number(i.waived_amount),0);
 const feesBalance=charges.reduce((a,f)=>a+Number(f.amount)-Number(f.paid_amount)-Number(f.waived_amount),0)+pending.reduce((a,f)=>a+f.amount,0);
 return NextResponse.json({loan,installments,charges,pendingFees:pending,payments:payments.data,principalBalance,feesBalance,totalBalance:principalBalance+feesBalance,renewalAmount:Number(loan.interest_amount)+feesBalance,negotiationAmount:installments.filter(i=>i.due_date<=today&&i.state!=='cancelled').reduce((a,i)=>a+Number(i.amount)-Number(i.paid_amount)-Number(i.waived_amount),0)+feesBalance});
}
