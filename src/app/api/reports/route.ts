import { NextRequest, NextResponse } from 'next/server';
import { requireTenant } from '@/lib/api';
import ExcelJS from 'exceljs';
import {PDFDocument,StandardFonts,rgb} from 'pdf-lib';
import { escapeCsvCell } from '@/lib/finance';
type Row = Record<string, unknown>;
const columns: Record<string, string[]> = {
  closures:['Data','Abertura','Entradas','Saídas','Fechamento','Observações'], overdue:['Contrato','Cliente','Parcela','Vencimento','Valor','Pago','Desconto','Estado'],
  clients: ['Nome','CPF','WhatsApp','Telefone','Cidade','Criado em'], loans: ['Contrato','Cliente','Modalidade','Estado','Principal','Juros %','Juros','Total','Início'],
  payments: ['Contrato','Cliente','Valor','Data','Observação'], expenses: ['Categoria','Valor','Data','Observação'], cash: ['Tipo','Descrição','Entrada/Saída','Valor','Data'], installments: ['Contrato','Cliente','Parcela','Vencimento','Valor','Pago','Desconto','Estado']
};
function related(row: Row, key: string): Row { const v=row[key];return v&&typeof v==='object'?v as Row:{} }
export async function GET(req: NextRequest) {
  const auth=await requireTenant(['master_admin','tenant_admin','employee'],'reports.export');if('response'in auth)return auth.response;
  const url=new URL(req.url),entity=url.searchParams.get('entity')||'clients',from=url.searchParams.get('from'),to=url.searchParams.get('to');
  if(!columns[entity])return NextResponse.json({error:'Relatório não suportado.'},{status:422});
  const db=auth.ctx.supabase!,tenant=auth.ctx.tenantId!,tenantName=auth.ctx.tenantName;let query;
  switch(entity){
    case 'closures':query=db.from('daily_closures').select('closure_date,opening_balance,entries,exits,closing_balance,notes').eq('tenant_id',tenant).order('closure_date');break;
    case 'clients': query=db.from('clients').select('full_name,cpf,whatsapp,phone,city,created_at').eq('tenant_id',tenant).eq('active',true).order('full_name');break;
    case 'loans': query=db.from('loans').select('contract_number,modality,state,principal,interest_percent,interest_amount,total_amount,start_date,clients(full_name)').eq('tenant_id',tenant).order('created_at',{ascending:false});break;
    case 'payments': query=db.from('payments').select('amount,paid_at,note,loans(contract_number,clients(full_name))').eq('tenant_id',tenant).is('reversed_at',null).order('paid_at',{ascending:false});break;
    case 'expenses': query=db.from('expenses').select('category,amount,expense_date,note').eq('tenant_id',tenant).is('reversed_at',null).order('expense_date',{ascending:false});break;
    case 'cash': query=db.from('ledger_movements').select('kind,description,direction,amount,occurred_at').eq('tenant_id',tenant).order('occurred_at',{ascending:false});break;
    default: query=db.from('installments').select('sequence,due_date,amount,paid_amount,waived_amount,state,loans(contract_number,clients(full_name))').eq('tenant_id',tenant).order('due_date',{ascending:true});
  }
  if(entity==='overdue')query=query.lt('due_date',new Intl.DateTimeFormat('en-CA',{timeZone:'America/Sao_Paulo'}).format(new Date())).in('state',['open','partial']);
  const field={closures:'closure_date',overdue:'due_date',clients:'created_at',loans:'start_date',payments:'paid_at',expenses:'expense_date',cash:'occurred_at',installments:'due_date'}[entity as 'clients'];
  const timestamp=['clients','payments','cash'].includes(entity);
  if((from&&!/^\d{4}-\d{2}-\d{2}$/.test(from))||(to&&!/^\d{4}-\d{2}-\d{2}$/.test(to)))return NextResponse.json({error:'Datas inválidas.'},{status:422});
  if(from)query=query.gte(field,timestamp?`${from}T00:00:00-03:00`:from);
  if(to)query=query.lte(field,timestamp?`${to}T23:59:59.999-03:00`:to);
  const rows:Row[]=[];
  for(let offset=0;offset<=10000;offset+=500){const {data,error}=await query.range(offset,offset+499);if(error)return NextResponse.json({error:'Não foi possível gerar o relatório.'},{status:500});rows.push(...(data||[]) as unknown as Row[]);if(rows.length>10000)return NextResponse.json({error:'Use um período menor para exportar até 10.000 registros por arquivo.'},{status:422});if(!data||data.length<500)break;}
  const values=rows.map(x=>{const loan=related(x,'loans'),client=related(loan,'clients');switch(entity){
    case 'closures':return [x.closure_date,x.opening_balance,x.entries,x.exits,x.closing_balance,x.notes];
    case 'clients':return [x.full_name,x.cpf,x.whatsapp,x.phone,x.city,x.created_at];
    case 'loans':{const c=related(x,'clients');return [x.contract_number,c.full_name,x.modality,x.state,x.principal,x.interest_percent,x.interest_amount,x.total_amount,x.start_date]}
    case 'payments':return [loan.contract_number,client.full_name,x.amount,x.paid_at,x.note];
    case 'expenses':return [x.category,x.amount,x.expense_date,x.note];
    case 'cash':return [x.kind,x.description,Number(x.direction)===1?'Entrada':'Saída',x.amount,x.occurred_at];
    default:return [loan.contract_number,client.full_name,x.sequence,x.due_date,x.amount,x.paid_amount,x.waived_amount,x.state];
  }});
  if(url.searchParams.get('format')==='pdf'){
   if(rows.length>1000)return NextResponse.json({error:'Use um período menor para exportar até 1.000 registros em PDF.'},{status:422});
   const pdf=await PDFDocument.create(),font=await pdf.embedFont(StandardFonts.Helvetica),bold=await pdf.embedFont(StandardFonts.HelveticaBold);
   let page=pdf.addPage([842,595]),y=550;const text=(value:unknown)=>String(value??'').replace(/[^\x20-\x7E\u00A0-\u00FF]/g,' ');
   function header(){page.drawText(text('ATLAS | '+tenantName),{x:32,y:555,size:17,font:bold,color:rgb(.07,.2,.36)});page.drawText(text(`${entity} | ${from||'Início'} a ${to||'Hoje'} | ${rows.length} registros`),{x:32,y:530,size:10,font});y=507;}
   header();for(const row of values){const line=row.map((value,i)=>`${columns[entity][i]}: ${text(value)}`).join(' | ');const words=line.split(' ');let chunk='';for(const word of words){if(font.widthOfTextAtSize(chunk+' '+word,9)>770){if(y<40){page=pdf.addPage([842,595]);header();}page.drawText(chunk,{x:32,y,size:9,font});y-=13;chunk=word;}else chunk+=(chunk?' ':'')+word;}if(y<40){page=pdf.addPage([842,595]);header();}page.drawText(chunk,{x:32,y,size:9,font});y-=22;}
   pdf.getPages().forEach((p,i)=>p.drawText(`ATLAS | ${i+1}/${pdf.getPageCount()}`,{x:32,y:20,size:8,font}));
   return new NextResponse(new Uint8Array(await pdf.save()),{headers:{'Content-Type':'application/pdf','Content-Disposition':`attachment; filename="atlas-${entity}.pdf"`,'Cache-Control':'private, no-store'}});
  }
  if(url.searchParams.get('format')==='xlsx'){
   const workbook=new ExcelJS.Workbook();const sheet=workbook.addWorksheet('ATLAS');sheet.addRow(columns[entity]);
   sheet.getRow(1).font={bold:true,color:{argb:'FFFFFFFF'}};sheet.getRow(1).fill={type:'pattern',pattern:'solid',fgColor:{argb:'FF13345D'}};
   values.forEach(row=>sheet.addRow(row.map(v=>typeof v==='number'?v:String(v??''))));sheet.columns.forEach(c=>{c.width=24});sheet.views=[{state:'frozen',ySplit:1}];
   const buffer=await workbook.xlsx.writeBuffer();return new NextResponse(new Uint8Array(buffer),{headers:{'Content-Type':'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','Content-Disposition':`attachment; filename="atlas-${entity}.xlsx"`,'Cache-Control':'private, no-store'}});
  }
  const csv='\uFEFF'+[columns[entity],...values].map(row=>row.map(escapeCsvCell).join(';')).join('\r\n');
  return new NextResponse(csv,{headers:{'Content-Type':'text/csv; charset=utf-8','Content-Disposition':`attachment; filename="atlas-${entity}.csv"`,'Cache-Control':'private, no-store'}});
}
