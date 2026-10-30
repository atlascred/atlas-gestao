import test from 'node:test';
import assert from 'node:assert/strict';
import { addMonthsPreservingBase, installmentAmounts, installmentDates, lateFee, simpleInterest, validCpf } from '../finance.ts';

test('calcula juros simples sem capitalização',()=>assert.equal(simpleInterest(1000,20),200));
test('distribui centavos e preserva o total',()=>assert.deepEqual(installmentAmounts(100,3),[33.34,33.33,33.33]));
test('preserva o dia-base após fevereiro',()=>{const d=addMonthsPreservingBase(new Date(2024,0,31),2,31);assert.equal(d.getFullYear(),2024);assert.equal(d.getMonth(),2);assert.equal(d.getDate(),31)});
test('diário exclui domingos sem reduzir parcelas',()=>{const dates=installmentDates(new Date(2026,9,31),'daily',2,false);assert.equal(dates.length,2);assert.ok(dates.every(d=>d.getDay()!==0))});
test('multas diárias só contam blocos completos',()=>{assert.equal(lateFee('daily',1,5,2),0);assert.equal(lateFee('daily',4,5,2),10)});
test('valida CPF pelos dígitos verificadores',()=>{assert.equal(validCpf('529.982.247-25'),true);assert.equal(validCpf('111.111.111-11'),false)});

test('juros arredondam metade para cima mesmo em limites decimais',()=>{
 assert.equal(simpleInterest(1,0.5),0.01);
 assert.equal(simpleInterest(100,1.005),1.01);
 assert.equal(simpleInterest(1000,0.005),0.05);
});
test('não cria parcelas de zero centavos',()=>assert.throws(()=>installmentAmounts(0.01,2)));
