import {z} from 'zod';
import {validCpf} from '@/lib/finance';
export const digits=(value:string)=>value.replace(/\D/g,'');
export function formatCpf(value:string){return digits(value).slice(0,11).replace(/^(\d{3})(\d)/,'$1.$2').replace(/^(\d{3})\.(\d{3})(\d)/,'$1.$2.$3').replace(/(\d{3})\.(\d{3})\.(\d{3})(\d)/,'$1.$2.$3-$4');}
export function formatCep(value:string){return digits(value).slice(0,8).replace(/^(\d{5})(\d)/,'$1-$2');}
export function formatPhone(value:string){let n=digits(value);if(n.length>11&&n.startsWith('55'))n=n.slice(2);n=n.slice(0,11);if(n.length<=2)return n;return `(${n.slice(0,2)}) ${n.length>10?n.slice(2,7):n.slice(2,6)}${n.length>(n.length>10?7:6)?'-'+n.slice(n.length>10?7:6):''}`;}
const text=(max:number)=>z.string().trim().max(max).optional().default('');
const cep=z.string().transform(digits).refine(v=>!v||v.length===8,'CEP deve ter 8 dígitos.').optional().default('');
const phone=z.string().transform(v=>{const n=digits(v);return n.length>11&&n.startsWith('55')?n.slice(2):n;}).refine(v=>!v||v.length===10||v.length===11,'Informe o DDD e o telefone.').optional().default('');
export const clientSchema=z.object({full_name:z.string().trim().min(2).max(180),cpf:z.string().transform(digits).refine(validCpf,'CPF inválido.'),postal_code:cep,address:text(240),address_number:text(30),neighborhood:text(120),city:text(120),whatsapp:phone,phone:phone,email:z.string().trim().toLowerCase().refine(v=>!v||z.email().safeParse(v).success,'E-mail inválido.').optional().default(''),reference_name:text(140),reference_relation:text(80),reference_phone:phone,reference_postal_code:cep,reference_address:text(240),housing_status:text(80),facebook:text(240),instagram:text(240),notes:text(4000)});
export type ClientForm=Record<keyof z.infer<typeof clientSchema>,string>;
export const emptyClient:ClientForm={full_name:'',cpf:'',postal_code:'',address:'',address_number:'',neighborhood:'',city:'',whatsapp:'',phone:'',email:'',reference_name:'',reference_relation:'',reference_phone:'',reference_postal_code:'',reference_address:'',housing_status:'',facebook:'',instagram:'',notes:''};
export const documentKinds=[['identity','Foto do RG'],['selfie','Selfie com documento'],['residence','Comprovante de residência'],['business','Comprovante do comércio'],['house_front','Foto da frente da casa (opcional)'],['business_front','Foto da frente do comércio (opcional)'],['pix','Comprovante PIX enviado ao cliente']] as const;
export const legacyDocumentKinds:Record<string,string>={professional:'Registro profissional',income:'Comprovante de renda',other:'Outro documento'};
