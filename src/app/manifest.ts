import type {MetadataRoute} from 'next';
export default function manifest():MetadataRoute.Manifest{return {name:'ATLAS Gestão Financeira',short_name:'ATLAS',description:'Gestão de clientes, empréstimos e operação financeira.',lang:'pt-BR',start_url:'/',display:'standalone',background_color:'#f7f8fa',theme_color:'#102c55',icons:[{src:'/logonovo.png',sizes:'any',type:'image/png',purpose:'any'}]};}
