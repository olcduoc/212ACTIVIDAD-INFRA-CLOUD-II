#!/bin/bash
ALB="http://tienda-tech-alb-785748890.us-east-1.elb.amazonaws.com:3001/api/productos"

curl -s -X POST "$ALB" -H "Content-Type: application/json" -d '{"nombre":"Laptop Dell XPS 15","descripcion":"Intel Core i7-13700H, 16GB RAM DDR5, 512GB SSD NVMe","precio":1299990,"stock":8}'
echo ""
curl -s -X POST "$ALB" -H "Content-Type: application/json" -d '{"nombre":"iPhone 15 Pro Max","descripcion":"256GB, Titanio Azul, Chip A17 Pro, USB-C","precio":1499990,"stock":5}'
echo ""
curl -s -X POST "$ALB" -H "Content-Type: application/json" -d '{"nombre":"Samsung Galaxy S24 Ultra","descripcion":"512GB, Negro Titanio, Snapdragon 8 Gen 3, S Pen","precio":1199990,"stock":12}'
echo ""
curl -s -X POST "$ALB" -H "Content-Type: application/json" -d '{"nombre":"MacBook Pro M3 Pro","descripcion":"14 pulgadas, Chip M3 Pro, 18GB RAM, 1TB SSD","precio":2199990,"stock":3}'
echo ""
curl -s -X POST "$ALB" -H "Content-Type: application/json" -d '{"nombre":"Sony WH-1000XM5","descripcion":"Audifonos Bluetooth Noise Cancelling, 30h bateria","precio":349990,"stock":20}'
echo ""
curl -s -X POST "$ALB" -H "Content-Type: application/json" -d '{"nombre":"iPad Air M2","descripcion":"11 pulgadas, 128GB WiFi, Chip M2, Azul Cielo","precio":749990,"stock":7}'
echo ""
echo "Carga completada"
