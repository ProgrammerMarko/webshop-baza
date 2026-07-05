# Webshop baza (PostgreSQL)

Shema baze podataka za web trgovinu kolekcionarskim novčanicama — projekt s
kolegija Napredni SQL (Veleučilište u Bjelovaru). Baza je zamišljena kao temelj
webshopa: korisnici i uloge, katalog s kategorijama i slikama, košarica,
narudžbe, zalihe, kuponi, načini dostave te potpun audit i inventurni trag.

Osim tablica, u shemi je i poslovna logika u PL/pgSQL-u: funkcije i triggeri
koji automatski skidaju zalihu pri narudžbi, vode audit log svake izmjene,
osvježavaju `updated_at` i broje iskorištenost kupona. Nekoliko admin
view-ova (pregled narudžbi, upozorenja o niskoj zalihi, dnevni prihod i profit)
služi za izvještaje.

## Postavljanje

Datoteke se učitavaju ovim redom u praznu PostgreSQL bazu:

```
psql -d webshop -f tables.sql
psql -d webshop -f psql.sql
psql -d webshop -f triggers.sql
psql -d webshop -f views.sql
```

Traži se ekstenzija `pgcrypto` (koristi se za UUID i hashiranje). Cijela shema
prolazi na čistoj bazi bez ručnih zahvata — 20 tablica i 25 triggera.

## Sadržaj

- `tables.sql` — tablice, ENUM tipovi, indeksi, JSONB metapodaci proizvoda
- `psql.sql` — PL/pgSQL funkcije (skidanje zaliha, audit, kuponi, bodovi)
- `triggers.sql` — triggeri koji te funkcije vežu na tablice
- `views.sql` — admin view-ovi za izvještaje
- ERD dijagram je u priloženom screenshotu

Napomena: shema je namijenjena kao backend sloj za Node.js webshop; ovdje je
samo baza podataka.
