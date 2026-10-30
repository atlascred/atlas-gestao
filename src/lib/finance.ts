export type Modality = 'daily' | 'weekly' | 'monthly';
function decimalFraction(value: number): [bigint,bigint] {
 if(!Number.isFinite(value))throw new Error('Valor numérico inválido.');
 const [mantissa, exponentText='0']=Math.abs(value).toString().toLowerCase().split('e');
 const [whole,fraction='']=mantissa.split('.');const exponent=Number(exponentText)-fraction.length;
 const digits=BigInt(whole+fraction)*(value<0?-1n:1n);
 return exponent>=0?[digits*10n**BigInt(exponent),1n]:[digits,10n**BigInt(-exponent)];
}
function halfUp(numerator:bigint,denominator:bigint):bigint{const sign=numerator<0n?-1n:1n;const abs=numerator*sign;return sign*((2n*abs+denominator)/(2n*denominator));}
export function roundMoney(value: number): number {const [n,d]=decimalFraction(value);return Number(halfUp(n*100n,d))/100;}
export function simpleInterest(principal: number, percent: number): number {const [p,pd]=decimalFraction(principal),[r,rd]=decimalFraction(percent);return Number(halfUp(p*r,pd*rd))/100;}
export function installmentAmounts(total: number, count: number): number[] {
  if (!Number.isInteger(count) || count < 1 || total <= 0) throw new Error('Informe um total e quantidade de parcelas válidos.');
  const cents = Math.round(roundMoney(total) * 100);
  if(cents<count)throw new Error('Cada parcela precisa ter pelo menos um centavo.');
  const base = Math.floor(cents / count), remainder = cents % count;
  return Array.from({length: count}, (_, i) => (base + (i < remainder ? 1 : 0)) / 100);
}
export function addMonthsPreservingBase(date: Date, months: number, baseDay = date.getDate()): Date {
  const targetMonth = date.getMonth() + months, year = date.getFullYear() + Math.floor(targetMonth / 12), month = ((targetMonth % 12) + 12) % 12;
  const day = Math.min(baseDay, new Date(year, month + 1, 0).getDate());
  return new Date(year, month, day, date.getHours(), date.getMinutes(), date.getSeconds(), date.getMilliseconds());
}
export function installmentDates(start: Date, modality: Modality, count: number, includeSundays = true): Date[] {
  if (count < 1 || !Number.isInteger(count)) throw new Error('A quantidade de parcelas precisa ser maior que zero.');
  if (modality === 'monthly') return Array.from({length:count},(_,i)=>addMonthsPreservingBase(start,i+1,start.getDate()));
  if (modality === 'weekly') return Array.from({length:count},(_,i)=>new Date(start.getFullYear(),start.getMonth(),start.getDate()+(i+1)*7));
  const result: Date[]=[]; const cursor=new Date(start.getFullYear(),start.getMonth(),start.getDate()+1);
  while(result.length<count){if(includeSundays||cursor.getDay()!==0)result.push(new Date(cursor));cursor.setDate(cursor.getDate()+1);}
  return result;
}
export function lateFee(modality: Modality, lateDays: number, fee: number, blockDays = 2, unpaidInstallments = 1): number {
  if (lateDays <= 0 || fee <= 0) return 0;
  if (modality === 'daily') return roundMoney(Math.floor(lateDays / Math.max(1,blockDays)) * fee);
  if (modality === 'weekly') return roundMoney(lateDays * fee * unpaidInstallments);
  return roundMoney(lateDays * fee);
}
export function validCpf(raw: string): boolean {
  const cpf=raw.replace(/\D/g,''); if(cpf.length!==11||/^([0-9])\1{10}$/.test(cpf))return false;
  for(let pos=9;pos<11;pos++){let sum=0;for(let i=0;i<pos;i++)sum+=Number(cpf[i])*(pos+1-i);const digit=(sum*10)%11%10;if(digit!==Number(cpf[pos]))return false;}
  return true;
}
export function escapeCsvCell(value: unknown): string { const text=String(value??'');const safe=/^[\s]*[=+@\-]/.test(text)?`'${text}`:text;return `"${safe.replaceAll('"','""')}"`; }
