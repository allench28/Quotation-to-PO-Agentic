import os
import csv
import boto3
from io import StringIO, BytesIO
from datetime import datetime
import sys
sys.path.append('/var/task/python')

# Note: Using text-based logo to avoid Pillow dependency

from fpdf import FPDF

s3_client = boto3.client('s3')

def generate_pdf_report(quotation_id, extracted_data, purchase_order):
    """Generate structured purchase order PDF matching PO_format.json"""
    bucket_name = os.environ.get('S3_BUCKET', 'quotation-processor-docs')
    
    pdf = FPDF()
    pdf.add_page()
    
    # Header
    pdf.set_font('Arial', 'B', 20)
    pdf.cell(0, 15, 'PURCHASE ORDER', 0, 1, 'C')
    pdf.ln(10)
    
    # PO Number and Date
    pdf.set_font('Arial', 'B', 12)
    po_number = purchase_order.get("po_number") or "N/A"
    po_date = purchase_order.get("po_date") or datetime.now().strftime("%Y-%m-%d")
    pdf.cell(95, 8, f'PO Number: {po_number}', 0, 0)
    pdf.cell(95, 8, f'Date: {po_date}', 0, 1)
    pdf.ln(10)
    
    # Supplier and Buyer sections side by side
    pdf.set_font('Arial', 'B', 12)
    pdf.cell(95, 8, 'SUPPLIER', 0, 0)
    pdf.cell(95, 8, 'BUYER', 0, 1)
    
    pdf.set_font('Arial', '', 10)
    # Supplier info (left side)
    company_name = extracted_data.get("company_name") or "N/A"
    address = extracted_data.get("address") or "N/A"
    phone = extracted_data.get("phone") or "N/A"
    email = extracted_data.get("email") or "N/A"
    
    pdf.cell(95, 6, company_name, 0, 0)
    # Buyer info (right side) - Fixed company details
    pdf.cell(95, 6, 'Axrail Demo Pte Ltd', 0, 1)
    
    pdf.cell(95, 6, address, 0, 0)
    pdf.cell(95, 6, 'Changi Tower, 78909 Singapore', 0, 1)
    
    pdf.cell(95, 6, f'Phone: {phone}', 0, 0)
    pdf.cell(95, 6, 'Phone: +65 56998 3421', 0, 1)
    
    pdf.cell(95, 6, f'Email: {email}', 0, 0)
    pdf.cell(95, 6, 'Email: contactus@axrail.com', 0, 1)
    pdf.ln(15)
    
    # Items Table
    pdf.set_font('Arial', 'B', 10)
    pdf.cell(80, 10, 'DESCRIPTION', 1, 0, 'C')
    pdf.cell(30, 10, 'QUANTITY', 1, 0, 'C')
    pdf.cell(40, 10, 'UNIT PRICE', 1, 0, 'C')
    pdf.cell(40, 10, 'TOTAL', 1, 1, 'C')
    
    # Table rows
    pdf.set_font('Arial', '', 9)
    for item in extracted_data.get('items', []):
        description = item.get("description") or "N/A"
        quantity = item.get("quantity") or 0
        unit_price = item.get("unit_price") or 0
        total_amount = item.get("total_amount") or 0
        
        pdf.cell(80, 8, description, 1, 0)
        pdf.cell(30, 8, str(quantity), 1, 0, 'C')
        pdf.cell(40, 8, f'${float(unit_price):.2f}', 1, 0, 'R')
        pdf.cell(40, 8, f'${float(total_amount):.2f}', 1, 1, 'R')
    
    # Summary section
    pdf.ln(10)
    pdf.set_font('Arial', 'B', 10)
    subtotal = extracted_data.get("subtotal") or 0
    tax = extracted_data.get("tax") or 0
    total = purchase_order.get("total") or 0
    
    pdf.cell(150, 8, 'Subtotal:', 0, 0, 'R')
    pdf.cell(40, 8, f'${float(subtotal):.2f}', 1, 1, 'R')
    pdf.cell(150, 8, 'Tax:', 0, 0, 'R')
    pdf.cell(40, 8, f'${float(tax):.2f}', 1, 1, 'R')
    pdf.set_font('Arial', 'B', 12)
    pdf.cell(150, 10, 'GRAND TOTAL:', 0, 0, 'R')
    pdf.cell(40, 10, f'${float(total):.2f}', 1, 1, 'R')
    
    # Add quotation reference at the bottom
    pdf.ln(15)
    pdf.set_font('Arial', '', 10)
    quote_ref = extracted_data.get('quote_number') or 'N/A'
    pdf.cell(0, 8, f'Quotation Reference: {quote_ref}', 0, 1, 'L')
    
    # Add centered Axrail footer with stylized text logo
    pdf.ln(15)
    
    # Create stylized AXRAIL logo with border
    pdf.set_line_width(0.5)
    pdf.set_draw_color(147, 112, 219)  # Light purple border
    pdf.rect(75, pdf.get_y(), 60, 15)  # Rectangle around logo
    
    pdf.set_font('Arial', 'B', 16)
    pdf.set_text_color(147, 112, 219)  # Light purple text
    pdf.cell(0, 15, 'A X R A I L', 0, 1, 'C')
    
    # Reset colors and add company info
    pdf.set_text_color(0, 0, 0)  # Black text
    pdf.set_draw_color(0, 0, 0)  # Black lines
    pdf.ln(5)
    
    pdf.set_font('Arial', 'B', 14)
    pdf.cell(0, 8, 'Axrail Demo Pte Ltd', 0, 1, 'C')
    pdf.set_font('Arial', '', 10)
    pdf.cell(0, 6, 'Changi Tower, 78909 Singapore', 0, 1, 'C')
    pdf.cell(0, 6, 'Phone: +65 56998 3421 | Email: contactus@axrail.com', 0, 1, 'C')
    
    pdf_buffer = BytesIO()
    pdf_content = pdf.output(dest='S')
    if isinstance(pdf_content, str):
        pdf_buffer.write(pdf_content.encode('latin1'))
    else:
        pdf_buffer.write(pdf_content)
    
    pdf_key = f"reports/{quotation_id}_purchase_order.pdf"
    
    s3_client.put_object(
        Bucket=bucket_name,
        Key=pdf_key,
        Body=pdf_buffer.getvalue(),
        ContentType='application/pdf'
    )
    
    return f"https://{bucket_name}.s3.amazonaws.com/{pdf_key}"

def generate_csv_report(quotation_id, extracted_data, purchase_order):
    """Generate CSV report and upload to S3 with public access"""
    bucket_name = os.environ.get('S3_BUCKET', 'quotation-processor-docs')
    
    csv_buffer = StringIO()
    writer = csv.writer(csv_buffer)
    
    # Header
    writer.writerow(['Report Type', 'Quotation Processing Data'])
    writer.writerow(['Generated', datetime.now().strftime('%Y-%m-%d %H:%M:%S')])
    writer.writerow([])
    
    # Extracted Data
    writer.writerow(['Section', 'Extracted Information'])
    writer.writerow(['Company', extracted_data.get('company_name', 'N/A')])
    writer.writerow(['Email', extracted_data.get('email', 'N/A')])
    writer.writerow(['Phone', extracted_data.get('phone', 'N/A')])
    writer.writerow(['Address', extracted_data.get('address', 'N/A')])
    writer.writerow(['Quote Number', extracted_data.get('quote_number', 'N/A')])
    writer.writerow(['Date', extracted_data.get('date', 'N/A')])
    writer.writerow(['Subtotal', extracted_data.get('subtotal', 0)])
    writer.writerow(['Tax', extracted_data.get('tax', 0) or 0])
    writer.writerow(['Total', extracted_data.get('total', 0) or extracted_data.get('subtotal', 0)])
    writer.writerow([])
    
    # Items
    writer.writerow(['Items'])
    writer.writerow(['Description', 'Quantity', 'Unit Price', 'Total Amount'])
    for item in extracted_data.get('items', []):
        writer.writerow([
            item.get('description', 'N/A'),
            item.get('quantity', 0),
            item.get('unit_price', 0),
            item.get('total_amount', 0)
        ])
    writer.writerow([])
    
    # Purchase Order
    writer.writerow(['Section', 'Purchase Order'])
    writer.writerow(['PO Number', purchase_order.get('po_number', 'N/A')])
    writer.writerow(['Vendor', purchase_order.get('vendor', 'N/A')])
    writer.writerow(['Vendor Email', purchase_order.get('vendor_email', 'N/A')])
    writer.writerow(['Vendor Phone', purchase_order.get('vendor_phone', 'N/A')])
    writer.writerow(['Vendor Address', purchase_order.get('vendor_address', 'N/A')])
    writer.writerow(['Status', purchase_order.get('status', 'N/A')])
    writer.writerow(['Total Amount', purchase_order.get('total', 0)])
    
    csv_key = f"reports/{quotation_id}_data.csv"
    
    s3_client.put_object(
        Bucket=bucket_name,
        Key=csv_key,
        Body=csv_buffer.getvalue(),
        ContentType='text/csv'
    )
    
    return f"https://{bucket_name}.s3.amazonaws.com/{csv_key}"

def generate_summary(extracted_data, purchase_order):
    """Generate processing summary"""
    items_count = len(extracted_data.get('items', []))
    total_amount = extracted_data.get('total', 0) or extracted_data.get('subtotal', 0)
    
    summary = {
        'processing_status': 'completed',
        'items_processed': items_count,
        'total_value': total_amount,
        'vendor': extracted_data.get('company_name', 'Unknown'),
        'po_generated': purchase_order.get('po_number'),
        'processing_time': datetime.now().isoformat()
    }
    
    return summary