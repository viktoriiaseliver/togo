import React from "react";
import { Button } from "./Button.jsx";
export function IconButton({ icon, label, size = "l", selected = false, disabled = false, onClick, color, variant = "surface", style }) {
  return <Button icon={icon} label={label} size={size} selected={selected} disabled={disabled} onClick={onClick} color={color} variant={variant} style={style} />;
}