import {NextResponse} from 'next/server';
export async function POST(){return NextResponse.json({error:'A recuperação por e-mail está desativada. Peça ao administrador para definir uma nova senha manualmente.'},{status:410});}
